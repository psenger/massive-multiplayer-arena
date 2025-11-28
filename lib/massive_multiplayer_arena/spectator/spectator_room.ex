defmodule MassiveMultiplayerArena.Spectator.SpectatorRoom do
  use GenServer
  alias MassiveMultiplayerArena.Spectator.{WebsocketHandler, StreamManager}

  defstruct [
    :game_id,
    :spectators,
    :stream_manager,
    :max_spectators,
    :pending_operations
  ]

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def join_spectator(game_id, spectator_id, websocket_pid) do
    GenServer.call(via_tuple(game_id), {:join_spectator, spectator_id, websocket_pid}, 5000)
  end

  def leave_spectator(game_id, spectator_id) do
    GenServer.call(via_tuple(game_id), {:leave_spectator, spectator_id}, 5000)
  end

  def broadcast_game_state(game_id, game_state) do
    GenServer.cast(via_tuple(game_id), {:broadcast_state, game_state})
  end

  def get_spectator_count(game_id) do
    GenServer.call(via_tuple(game_id), :get_spectator_count)
  end

  def init(game_id) do
    {:ok, stream_manager} = StreamManager.start_link(game_id)
    
    state = %__MODULE__{
      game_id: game_id,
      spectators: %{},
      stream_manager: stream_manager,
      max_spectators: 100,
      pending_operations: MapSet.new()
    }
    
    {:ok, state}
  end

  def handle_call({:join_spectator, spectator_id, websocket_pid}, from, state) do
    # Check if operation is already pending to prevent race conditions
    if MapSet.member?(state.pending_operations, spectator_id) do
      {:reply, {:error, :operation_pending}, state}
    else
      # Mark operation as pending
      new_pending = MapSet.put(state.pending_operations, spectator_id)
      
      case do_join_spectator(spectator_id, websocket_pid, %{state | pending_operations: new_pending}) do
        {:ok, new_state} ->
          # Remove from pending operations
          final_state = %{new_state | pending_operations: MapSet.delete(new_state.pending_operations, spectator_id)}
          {:reply, :ok, final_state}
        
        {:error, reason, new_state} ->
          # Remove from pending operations
          final_state = %{new_state | pending_operations: MapSet.delete(new_state.pending_operations, spectator_id)}
          {:reply, {:error, reason}, final_state}
      end
    end
  end

  def handle_call({:leave_spectator, spectator_id}, _from, state) do
    # Check if operation is already pending
    if MapSet.member?(state.pending_operations, spectator_id) do
      {:reply, {:error, :operation_pending}, state}
    else
      # Mark operation as pending
      new_pending = MapSet.put(state.pending_operations, spectator_id)
      
      case do_leave_spectator(spectator_id, %{state | pending_operations: new_pending}) do
        {:ok, new_state} ->
          # Remove from pending operations
          final_state = %{new_state | pending_operations: MapSet.delete(new_state.pending_operations, spectator_id)}
          {:reply, :ok, final_state}
        
        {:error, reason, new_state} ->
          # Remove from pending operations  
          final_state = %{new_state | pending_operations: MapSet.delete(new_state.pending_operations, spectator_id)}
          {:reply, {:error, reason}, final_state}
      end
    end
  end

  def handle_call(:get_spectator_count, _from, state) do
    {:reply, map_size(state.spectators), state}
  end

  def handle_cast({:broadcast_state, game_state}, state) do
    Enum.each(state.spectators, fn {_spectator_id, websocket_pid} ->
      if Process.alive?(websocket_pid) do
        WebsocketHandler.send_game_state(websocket_pid, game_state)
      end
    end)
    
    StreamManager.broadcast_state(state.stream_manager, game_state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up spectator whose process died
    spectator_id = find_spectator_by_pid(state.spectators, pid)
    
    case spectator_id do
      nil ->
        {:noreply, state}
      
      id ->
        new_spectators = Map.delete(state.spectators, id)
        {:noreply, %{state | spectators: new_spectators}}
    end
  end

  defp do_join_spectator(spectator_id, websocket_pid, state) do
    cond do
      Map.has_key?(state.spectators, spectator_id) ->
        {:error, :already_joined, state}
        
      map_size(state.spectators) >= state.max_spectators ->
        {:error, :room_full, state}
        
      !Process.alive?(websocket_pid) ->
        {:error, :invalid_websocket, state}
        
      true ->
        Process.monitor(websocket_pid)
        new_spectators = Map.put(state.spectators, spectator_id, websocket_pid)
        {:ok, %{state | spectators: new_spectators}}
    end
  end

  defp do_leave_spectator(spectator_id, state) do
    case Map.get(state.spectators, spectator_id) do
      nil ->
        {:error, :not_found, state}
        
      _websocket_pid ->
        new_spectators = Map.delete(state.spectators, spectator_id)
        {:ok, %{state | spectators: new_spectators}}
    end
  end

  defp find_spectator_by_pid(spectators, pid) do
    Enum.find_value(spectators, fn {spectator_id, spectator_pid} ->
      if spectator_pid == pid, do: spectator_id
    end)
  end

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.SpectatorRegistry, game_id}}
  end
end