defmodule MassiveMultiplayerArena.Spectator.SpectatorRoom do
  @moduledoc """
  Manages spectator connections and real-time game viewing with streaming support.
  """

  use GenServer
  alias MassiveMultiplayerArena.GameEngine.GameServer
  alias MassiveMultiplayerArena.Spectator.{ReplaySystem, StreamManager}
  require Logger

  defstruct [
    :game_id,
    :spectators,
    :replay_pid,
    :stream_manager_pid,
    :game_server_pid,
    :last_update
  ]

  # Client API

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def join_spectator(game_id, spectator_id, opts \\ []) do
    GenServer.call(via_tuple(game_id), {:join_spectator, spectator_id, opts})
  end

  def leave_spectator(game_id, spectator_id) do
    GenServer.call(via_tuple(game_id), {:leave_spectator, spectator_id})
  end

  def get_spectator_count(game_id) do
    GenServer.call(via_tuple(game_id), :get_spectator_count)
  end

  def broadcast_game_update(game_id, game_state) do
    GenServer.cast(via_tuple(game_id), {:broadcast_game_update, game_state})
  end

  def get_current_game_state(game_id) do
    GenServer.call(via_tuple(game_id), :get_current_game_state)
  end

  # New streaming functions
  def send_hls_segment(viewer_id, data) do
    # Implementation for HLS segment delivery
    send_to_viewer(viewer_id, {:hls_segment, data})
  end

  def send_webrtc_data(viewer_id, data) do
    # Implementation for WebRTC data channel
    send_to_viewer(viewer_id, {:webrtc_data, data})
  end

  def send_dash_segment(viewer_id, data) do
    # Implementation for DASH segment delivery
    send_to_viewer(viewer_id, {:dash_segment, data})
  end

  def notify_viewer(viewer_id, message) do
    send_to_viewer(viewer_id, {:notification, message})
  end

  # Server Implementation

  def init(game_id) do
    # Start replay system
    {:ok, replay_pid} = ReplaySystem.start_link(game_id: game_id)
    
    # Start stream manager
    {:ok, stream_manager_pid} = StreamManager.start_link(game_id: game_id)
    
    # Get game server PID
    game_server_pid = GameServer.get_pid(game_id)
    
    state = %__MODULE__{
      game_id: game_id,
      spectators: %{},
      replay_pid: replay_pid,
      stream_manager_pid: stream_manager_pid,
      game_server_pid: game_server_pid,
      last_update: System.system_time(:millisecond)
    }

    Logger.info("Spectator room started for game: #{game_id}")
    {:ok, state}
  end

  def handle_call({:join_spectator, spectator_id, opts}, _from, state) do
    stream_format = Keyword.get(opts, :stream_format, :webrtc)
    stream_quality = Keyword.get(opts, :stream_quality, :medium)
    
    case Map.get(state.spectators, spectator_id) do
      nil ->
        # New spectator
        spectator = %{
          id: spectator_id,
          joined_at: System.system_time(:millisecond),
          stream_format: stream_format,
          stream_quality: stream_quality,
          stream_id: nil
        }
        
        # Start or assign to existing stream
        case StreamManager.start_stream(state.game_id, stream_format, stream_quality) do
          {:ok, stream_id} ->
            updated_spectator = %{spectator | stream_id: stream_id}
            StreamManager.add_viewer(state.game_id, spectator_id, stream_id)
            
            updated_spectators = Map.put(state.spectators, spectator_id, updated_spectator)
            new_state = %{state | spectators: updated_spectators}
            
            # Send current game state to new spectator
            current_state = get_game_state_from_server(state.game_server_pid)
            send_to_spectator(spectator_id, {:initial_state, current_state})
            
            Logger.info("Spectator #{spectator_id} joined game #{state.game_id} with #{stream_format}/#{stream_quality}")
            {:reply, {:ok, %{spectator_count: map_size(updated_spectators)}}, new_state}
          
          {:error, reason} ->
            Logger.error("Failed to start stream for spectator #{spectator_id}: #{reason}")
            {:reply, {:error, :stream_unavailable}, state}
        end
      
      _existing ->
        # Spectator already exists
        {:reply, {:error, :already_joined}, state}
    end
  end

  def handle_call({:leave_spectator, spectator_id}, _from, state) do
    case Map.get(state.spectators, spectator_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      spectator ->
        # Remove from stream manager
        StreamManager.remove_viewer(state.game_id, spectator_id)
        
        updated_spectators = Map.delete(state.spectators, spectator_id)
        new_state = %{state | spectators: updated_spectators}
        
        Logger.info("Spectator #{spectator_id} left game #{state.game_id}")
        {:reply, {:ok, %{spectator_count: map_size(updated_spectators)}}, new_state}
    end
  end

  def handle_call(:get_spectator_count, _from, state) do
    {:reply, map_size(state.spectators), state}
  end

  def handle_call(:get_current_game_state, _from, state) do
    current_state = get_game_state_from_server(state.game_server_pid)
    {:reply, current_state, state}
  end

  def handle_cast({:broadcast_game_update, game_state}, state) do
    # Record in replay system
    ReplaySystem.record_frame(state.game_id, game_state)
    
    # Broadcast through stream manager
    StreamManager.broadcast_game_data(state.game_id, game_state)
    
    # Send to individual spectators (fallback/legacy)
    Enum.each(state.spectators, fn {spectator_id, _spectator} ->
      send_to_spectator(spectator_id, {:game_update, game_state})
    end)
    
    new_state = %{state | last_update: System.system_time(:millisecond)}
    {:noreply, new_state}
  end

  # Private Functions

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.Registry, {__MODULE__, game_id}}}
  end

  defp send_to_spectator(spectator_id, message) do
    # Send message to spectator via WebSocket or other transport
    case Registry.lookup(MassiveMultiplayerArena.Registry, {:websocket, spectator_id}) do
      [{pid, _}] ->
        send(pid, message)
      
      [] ->
        Logger.debug("Spectator #{spectator_id} websocket not found")
    end
  end

  defp send_to_viewer(viewer_id, message) do
    # Generic function to send messages to viewers
    send_to_spectator(viewer_id, message)
  end

  defp get_game_state_from_server(game_server_pid) do
    if Process.alive?(game_server_pid) do
      GameServer.get_game_state(game_server_pid)
    else
      nil
    end
  end
end