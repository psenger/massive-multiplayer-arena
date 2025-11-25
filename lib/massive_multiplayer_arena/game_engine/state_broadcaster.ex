defmodule MassiveMultiplayerArena.GameEngine.StateBroadcaster do
  @moduledoc """
  Optimized state broadcasting with delta compression and selective updates.
  """

  use GenServer
  require Logger

  alias MassiveMultiplayerArena.GameEngine.GameState

  defstruct [
    :game_id,
    :subscribers,
    :broadcast_interval,
    :last_full_broadcast,
    :compression_enabled
  ]

  @broadcast_interval 50  # milliseconds
  @full_state_interval 5000  # milliseconds

  # Client API

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(game_id))
  end

  def subscribe(game_id, subscriber_pid) do
    GenServer.call(via_tuple(game_id), {:subscribe, subscriber_pid})
  end

  def unsubscribe(game_id, subscriber_pid) do
    GenServer.call(via_tuple(game_id), {:unsubscribe, subscriber_pid})
  end

  def broadcast_state(game_id, game_state) do
    GenServer.cast(via_tuple(game_id), {:broadcast_state, game_state})
  end

  def set_compression(game_id, enabled) do
    GenServer.cast(via_tuple(game_id), {:set_compression, enabled})
  end

  # Server callbacks

  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    compression_enabled = Keyword.get(opts, :compression, true)
    
    schedule_broadcast()
    
    state = %__MODULE__{
      game_id: game_id,
      subscribers: MapSet.new(),
      broadcast_interval: @broadcast_interval,
      last_full_broadcast: DateTime.utc_now(),
      compression_enabled: compression_enabled
    }
    
    Logger.info("State broadcaster started for game #{game_id}")
    {:ok, state}
  end

  def handle_call({:subscribe, subscriber_pid}, _from, state) do
    Process.monitor(subscriber_pid)
    new_subscribers = MapSet.put(state.subscribers, subscriber_pid)
    
    Logger.debug("Subscriber #{inspect(subscriber_pid)} added to game #{state.game_id}")
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  def handle_call({:unsubscribe, subscriber_pid}, _from, state) do
    new_subscribers = MapSet.delete(state.subscribers, subscriber_pid)
    
    Logger.debug("Subscriber #{inspect(subscriber_pid)} removed from game #{state.game_id}")
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  def handle_cast({:broadcast_state, game_state}, state) do
    broadcast_to_subscribers(state, game_state)
    {:noreply, state}
  end

  def handle_cast({:set_compression, enabled}, state) do
    Logger.info("Compression #{if enabled, do: "enabled", else: "disabled"} for game #{state.game_id}")
    {:noreply, %{state | compression_enabled: enabled}}
  end

  def handle_info(:broadcast_tick, state) do
    schedule_broadcast()
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    Logger.debug("Subscriber #{inspect(pid)} removed due to process exit")
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.GameRegistry, {:state_broadcaster, game_id}}}
  end

  defp schedule_broadcast do
    Process.send_after(self(), :broadcast_tick, @broadcast_interval)
  end

  defp broadcast_to_subscribers(state, game_state) do
    now = DateTime.utc_now()
    time_since_full = DateTime.diff(now, state.last_full_broadcast, :millisecond)
    
    should_send_full = time_since_full >= @full_state_interval
    
    message = if should_send_full do
      full_state = GameState.get_full_state(game_state)
      {:game_state_full, full_state}
    else
      {delta_updates, _updated_state} = GameState.get_delta_updates(game_state)
      
      if Enum.empty?(delta_updates) do
        nil
      else
        compressed_updates = if state.compression_enabled do
          compress_delta_updates(delta_updates)
        else
          delta_updates
        end
        
        {:game_state_delta, compressed_updates}
      end
    end
    
    if message do
      broadcast_message = {
        :state_update,
        %{
          game_id: state.game_id,
          tick: game_state.tick_count,
          timestamp: DateTime.to_unix(now, :millisecond),
          data: message
        }
      }
      
      Enum.each(state.subscribers, fn subscriber ->
        send(subscriber, broadcast_message)
      end)
      
      Logger.debug("Broadcasted #{elem(message, 0)} to #{MapSet.size(state.subscribers)} subscribers")
    end
    
    updated_state = if should_send_full do
      %{state | last_full_broadcast: now}
    else
      state
    end
    
    updated_state
  end

  defp compress_delta_updates(updates) do
    # Group updates by type and entity for further compression
    updates
    |> Enum.group_by(&get_update_key/1)
    |> Enum.map(fn {_key, grouped_updates} ->
      case grouped_updates do
        [single_update] -> single_update
        multiple_updates -> merge_updates(multiple_updates)
      end
    end)
  end

  defp get_update_key(update) do
    case update do
      %{type: :player_updated, player_id: id} -> {:player, id}
      %{type: :projectile_updated, projectile_id: id} -> {:projectile, id}
      %{type: type} -> type
    end
  end

  defp merge_updates([first_update | rest]) do
    Enum.reduce(rest, first_update, fn update, acc ->
      case {acc, update} do
        {%{changes: acc_changes}, %{changes: update_changes}} ->
          Map.put(acc, :changes, Map.merge(acc_changes, update_changes))
        _ ->
          update  # Use the latest update if they can't be merged
      end
    end)
  end
end