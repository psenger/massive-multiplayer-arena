defmodule MassiveMultiplayerArena.Spectator.ReplayManager do
  @moduledoc """
  Manages replay systems for multiple games and provides
  high-level interface for replay operations.
  """

  use GenServer
  alias MassiveMultiplayerArena.Spectator.ReplaySystem
  require Logger

  defstruct [
    :active_replays,
    :replay_metadata
  ]

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def create_replay(game_id) do
    GenServer.call(__MODULE__, {:create_replay, game_id})
  end

  def start_recording(game_id) do
    GenServer.call(__MODULE__, {:start_recording, game_id})
  end

  def stop_recording(game_id) do
    GenServer.call(__MODULE__, {:stop_recording, game_id})
  end

  def get_available_replays() do
    GenServer.call(__MODULE__, :get_available_replays)
  end

  def get_replay(game_id) do
    GenServer.call(__MODULE__, {:get_replay, game_id})
  end

  def record_game_event(game_id, game_state) do
    GenServer.cast(__MODULE__, {:record_game_event, game_id, game_state})
  end

  def cleanup_replay(game_id) do
    GenServer.call(__MODULE__, {:cleanup_replay, game_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_replays: %{},
      replay_metadata: %{}
    }
    
    Logger.info("Replay manager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_replay, game_id}, _from, state) do
    case Map.get(state.active_replays, game_id) do
      nil ->
        case ReplaySystem.start_link(game_id) do
          {:ok, pid} ->
            metadata = create_replay_metadata(game_id)
            
            new_state = %{state |
              active_replays: Map.put(state.active_replays, game_id, pid),
              replay_metadata: Map.put(state.replay_metadata, game_id, metadata)
            }
            
            Logger.info("Created replay system for game #{game_id}")
            {:reply, {:ok, pid}, new_state}
            
          {:error, reason} ->
            Logger.error("Failed to create replay system for game #{game_id}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
        
      _existing_pid ->
        {:reply, {:error, :already_exists}, state}
    end
  end

  @impl true
  def handle_call({:start_recording, game_id}, _from, state) do
    case Map.get(state.active_replays, game_id) do
      nil ->
        {:reply, {:error, :replay_not_found}, state}
        
      _pid ->
        result = ReplaySystem.start_recording(game_id)
        
        if result == :ok do
          metadata = Map.get(state.replay_metadata, game_id)
          updated_metadata = %{metadata | recording: true, start_time: System.system_time(:second)}
          
          new_state = %{state |
            replay_metadata: Map.put(state.replay_metadata, game_id, updated_metadata)
          }
          
          {:reply, :ok, new_state}
        else
          {:reply, result, state}
        end
    end
  end

  @impl true
  def handle_call({:stop_recording, game_id}, _from, state) do
    case Map.get(state.active_replays, game_id) do
      nil ->
        {:reply, {:error, :replay_not_found}, state}
        
      _pid ->
        result = ReplaySystem.stop_recording(game_id)
        
        if result == :ok do
          metadata = Map.get(state.replay_metadata, game_id)
          updated_metadata = %{metadata | recording: false, end_time: System.system_time(:second)}
          
          new_state = %{state |
            replay_metadata: Map.put(state.replay_metadata, game_id, updated_metadata)
          }
          
          {:reply, :ok, new_state}
        else
          {:reply, result, state}
        end
    end
  end

  @impl true
  def handle_call(:get_available_replays, _from, state) do
    replays = Enum.map(state.replay_metadata, fn {game_id, metadata} ->
      Map.put(metadata, :game_id, game_id)
    end)
    
    {:reply, replays, state}
  end

  @impl true
  def handle_call({:get_replay, game_id}, _from, state) do
    case Map.get(state.active_replays, game_id) do
      nil ->
        {:reply, {:error, :replay_not_found}, state}
        
      _pid ->
        replay_data = ReplaySystem.get_replay_data(game_id)
        metadata = Map.get(state.replay_metadata, game_id)
        
        full_replay = Map.merge(replay_data, metadata)
        {:reply, {:ok, full_replay}, state}
    end
  end

  @impl true
  def handle_call({:cleanup_replay, game_id}, _from, state) do
    case Map.get(state.active_replays, game_id) do
      nil ->
        {:reply, {:error, :replay_not_found}, state}
        
      pid ->
        Process.exit(pid, :normal)
        
        new_state = %{state |
          active_replays: Map.delete(state.active_replays, game_id),
          replay_metadata: Map.delete(state.replay_metadata, game_id)
        }
        
        Logger.info("Cleaned up replay for game #{game_id}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:record_game_event, game_id, game_state}, state) do
    case Map.get(state.active_replays, game_id) do
      nil ->
        {:noreply, state}
        
      _pid ->
        ReplaySystem.record_snapshot(game_id, game_state)
        {:noreply, state}
    end
  end

  ## Private Functions

  defp create_replay_metadata(game_id) do
    %{
      created_at: System.system_time(:second),
      recording: false,
      start_time: nil,
      end_time: nil,
      game_id: game_id,
      version: "1.0"
    }
  end
end