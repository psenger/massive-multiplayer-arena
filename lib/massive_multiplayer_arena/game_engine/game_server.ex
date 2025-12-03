defmodule MassiveMultiplayerArena.GameEngine.GameServer do
  use GenServer
  alias MassiveMultiplayerArena.GameEngine.{GameState, Player, Collision, Physics, WorldBounds}
  require Logger

  @tick_rate 60
  @tick_interval div(1000, @tick_rate)

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def init(game_id) do
    Logger.info("Starting game server for game #{game_id}")

    state = %{
      game_id: game_id,
      game_state: GameState.new(game_id),
      tick_timer: schedule_tick(),
      connected_players: MapSet.new()
    }

    {:ok, state}
  end

  def add_player(game_id, player_id, player_data) do
    GenServer.call(via_tuple(game_id), {:add_player, player_id, player_data})
  end

  def remove_player(game_id, player_id) do
    GenServer.call(via_tuple(game_id), {:remove_player, player_id})
  end

  def handle_player_input(game_id, player_id, input) do
    GenServer.cast(via_tuple(game_id), {:player_input, player_id, input})
  end

  def get_game_state(game_id) do
    GenServer.call(via_tuple(game_id), :get_game_state)
  end

  def handle_call({:add_player, player_id, player_data}, _from, state) do
    Logger.info("Adding player #{player_id} to game #{state.game_id}")
    
    player = Player.new(player_id, player_data)
    updated_game_state = GameState.add_player(state.game_state, player)
    connected_players = MapSet.put(state.connected_players, player_id)
    
    updated_state = %{state | 
      game_state: updated_game_state,
      connected_players: connected_players
    }
    
    # Monitor the player process to detect disconnections
    Process.monitor(self())
    
    {:reply, :ok, updated_state}
  end

  def handle_call({:remove_player, player_id}, _from, state) do
    Logger.info("Removing player #{player_id} from game #{state.game_id}")
    
    updated_game_state = GameState.remove_player(state.game_state, player_id)
    connected_players = MapSet.delete(state.connected_players, player_id)
    
    updated_state = %{state | 
      game_state: updated_game_state,
      connected_players: connected_players
    }
    
    # Check if game should be terminated
    if MapSet.size(connected_players) == 0 do
      Logger.info("No players left in game #{state.game_id}, scheduling shutdown")
      Process.send_after(self(), :shutdown_empty_game, 30_000)
    end
    
    {:reply, :ok, updated_state}
  end

  def handle_call(:get_game_state, _from, state) do
    {:reply, state.game_state, state}
  end

  def handle_cast({:player_input, player_id, input}, state) do
    # Validate player is still connected
    if MapSet.member?(state.connected_players, player_id) do
      updated_game_state = GameState.update_player_input(state.game_state, player_id, input)
      updated_state = %{state | game_state: updated_game_state}
      {:noreply, updated_state}
    else
      Logger.warn("Ignoring input from disconnected player #{player_id}")
      {:noreply, state}
    end
  end

  def handle_info(:tick, state) do
    # Update physics and collisions
    updated_game_state = state.game_state
                        |> Physics.update_positions(@tick_interval / 1000)
                        |> WorldBounds.enforce_bounds()
                        |> Collision.check_collisions()
    
    # Broadcast state to connected players
    broadcast_game_state(state.game_id, updated_game_state, state.connected_players)
    
    updated_state = %{state | 
      game_state: updated_game_state,
      tick_timer: schedule_tick()
    }
    
    {:noreply, updated_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle process monitoring for player disconnections
    # This would need to be enhanced with proper player-process mapping
    Logger.info("Process down detected in game #{state.game_id}")
    {:noreply, state}
  end

  def handle_info(:shutdown_empty_game, state) do
    if MapSet.size(state.connected_players) == 0 do
      Logger.info("Shutting down empty game #{state.game_id}")
      {:stop, :normal, state}
    else
      Logger.info("Game #{state.game_id} no longer empty, cancelling shutdown")
      {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.warn("Unhandled message in GameServer: #{inspect(msg)}")
    {:noreply, state}
  end

  def terminate(reason, state) do
    Logger.info("Game server #{state.game_id} terminating: #{inspect(reason)}")
    
    # Cleanup: notify all connected players
    Enum.each(state.connected_players, fn player_id ->
      # Send game ended notification to player
      send_to_player(player_id, {:game_ended, state.game_id, reason})
    end)
    
    :ok
  end

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.GameRegistry, "game:#{game_id}"}}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp broadcast_game_state(game_id, game_state, connected_players) do
    message = {:game_state_update, game_id, game_state}
    
    Enum.each(connected_players, fn player_id ->
      send_to_player(player_id, message)
    end)
  end

  defp send_to_player(player_id, message) do
    # This would integrate with your WebSocket/TCP connection system
    # For now, we'll just log the action
    Logger.debug("Sending to player #{player_id}: #{inspect(message)}")
  end
end