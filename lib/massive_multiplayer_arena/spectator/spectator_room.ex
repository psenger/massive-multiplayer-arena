defmodule MassiveMultiplayerArena.Spectator.SpectatorRoom do
  @moduledoc """
  Manages spectator rooms for live game viewing.
  """

  use GenServer
  require Logger

  alias MassiveMultiplayerArena.GameEngine.GameServer

  defstruct [
    :game_id,
    :spectators,
    :last_state,
    :room_id
  ]

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    room_id = "spectator_#{game_id}"
    GenServer.start_link(__MODULE__, opts, name: {:global, room_id})
  end

  def join_spectator(room_id, spectator_pid) do
    GenServer.call({:global, room_id}, {:join, spectator_pid})
  end

  def leave_spectator(room_id, spectator_pid) do
    GenServer.call({:global, room_id}, {:leave, spectator_pid})
  end

  def broadcast_game_state(room_id, game_state) do
    GenServer.cast({:global, room_id}, {:broadcast_state, game_state})
  end

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    room_id = "spectator_#{game_id}"
    
    # Subscribe to game state updates
    Phoenix.PubSub.subscribe(MassiveMultiplayerArena.PubSub, "game:#{game_id}")
    
    Logger.info("Spectator room started for game #{game_id}")
    
    {:ok, %__MODULE__{
      game_id: game_id,
      room_id: room_id,
      spectators: MapSet.new(),
      last_state: nil
    }}
  end

  @impl true
  def handle_call({:join, spectator_pid}, _from, state) do
    Process.monitor(spectator_pid)
    new_spectators = MapSet.put(state.spectators, spectator_pid)
    
    # Send current game state if available
    if state.last_state do
      send(spectator_pid, {:game_state_update, state.last_state})
    end
    
    Logger.info("Spectator joined room #{state.room_id}. Total: #{MapSet.size(new_spectators)}")
    
    {:reply, :ok, %{state | spectators: new_spectators}}
  end

  @impl true
  def handle_call({:leave, spectator_pid}, _from, state) do
    new_spectators = MapSet.delete(state.spectators, spectator_pid)
    
    Logger.info("Spectator left room #{state.room_id}. Total: #{MapSet.size(new_spectators)}")
    
    # Stop room if no spectators remain
    if MapSet.size(new_spectators) == 0 do
      {:stop, :normal, :ok, state}
    else
      {:reply, :ok, %{state | spectators: new_spectators}}
    end
  end

  @impl true
  def handle_cast({:broadcast_state, game_state}, state) do
    # Broadcast to all spectators
    Enum.each(state.spectators, fn spectator_pid ->
      send(spectator_pid, {:game_state_update, game_state})
    end)
    
    {:noreply, %{state | last_state: game_state}}
  end

  @impl true
  def handle_info({:game_state_update, game_state}, state) do
    # Received game state update from PubSub
    handle_cast({:broadcast_state, game_state}, state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Handle spectator process crash/disconnect
    new_spectators = MapSet.delete(state.spectators, pid)
    
    Logger.info("Spectator process down in room #{state.room_id}. Total: #{MapSet.size(new_spectators)}")
    
    if MapSet.size(new_spectators) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, %{state | spectators: new_spectators}}
    end
  end
end