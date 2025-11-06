defmodule MassiveMultiplayerArena.GameEngine.GameServer do
  @moduledoc """
  GenServer managing individual game instances with real-time combat mechanics.
  Handles player actions, collision detection, and game state updates.
  """

  use GenServer
  require Logger

  alias MassiveMultiplayerArena.GameEngine.{GameState, Physics, Combat}
  alias MassiveMultiplayerArena.Spectator.ReplayRecorder

  @tick_interval 16  # ~60 FPS
  @max_players 10

  defstruct [
    :game_id,
    :state,
    :players,
    :spectators,
    :last_tick,
    :replay_recorder
  ]

  ## Client API

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def join_player(game_id, player_id, player_data) do
    GenServer.call(via_tuple(game_id), {:join_player, player_id, player_data})
  end

  def player_action(game_id, player_id, action) do
    GenServer.cast(via_tuple(game_id), {:player_action, player_id, action})
  end

  def add_spectator(game_id, spectator_id) do
    GenServer.call(via_tuple(game_id), {:add_spectator, spectator_id})
  end

  def get_state(game_id) do
    GenServer.call(via_tuple(game_id), :get_state)
  end

  ## Server Implementation

  @impl true
  def init(game_id) do
    Logger.info("Starting game server for game #{game_id}")
    
    state = %__MODULE__{
      game_id: game_id,
      state: GameState.new(),
      players: %{},
      spectators: MapSet.new(),
      last_tick: System.monotonic_time(:millisecond),
      replay_recorder: ReplayRecorder.start_recording(game_id)
    }
    
    schedule_tick()
    {:ok, state}
  end

  @impl true
  def handle_call({:join_player, player_id, player_data}, _from, state) do
    cond do
      map_size(state.players) >= @max_players ->
        {:reply, {:error, :game_full}, state}
      
      Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :already_joined}, state}
      
      true ->
        updated_state = GameState.add_player(state.state, player_id, player_data)
        new_players = Map.put(state.players, player_id, player_data)
        
        broadcast_state_update(state.game_id, updated_state)
        
        {:reply, :ok, %{state | state: updated_state, players: new_players}}
    end
  end

  @impl true
  def handle_call({:add_spectator, spectator_id}, _from, state) do
    new_spectators = MapSet.put(state.spectators, spectator_id)
    {:reply, :ok, %{state | spectators: new_spectators}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_cast({:player_action, player_id, action}, state) do
    if Map.has_key?(state.players, player_id) do
      updated_state = Combat.process_action(state.state, player_id, action)
      ReplayRecorder.record_action(state.replay_recorder, player_id, action)
      
      {:noreply, %{state | state: updated_state}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    current_time = System.monotonic_time(:millisecond)
    delta_time = current_time - state.last_tick
    
    # Update physics and game logic
    updated_state = state.state
    |> Physics.update(delta_time)
    |> Combat.update_cooldowns(delta_time)
    |> GameState.check_win_conditions()
    
    # Broadcast to players and spectators
    broadcast_state_update(state.game_id, updated_state)
    
    # Record for replay
    ReplayRecorder.record_frame(state.replay_recorder, updated_state)
    
    schedule_tick()
    
    {:noreply, %{state | state: updated_state, last_tick: current_time}}
  end

  ## Private Functions

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.GameRegistry, game_id}}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp broadcast_state_update(game_id, game_state) do
    Phoenix.PubSub.broadcast(
      MassiveMultiplayerArena.PubSub,
      "game:#{game_id}",
      {:game_update, game_state}
    )
  end
end