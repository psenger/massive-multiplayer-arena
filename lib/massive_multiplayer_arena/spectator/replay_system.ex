defmodule MassiveMultiplayerArena.Spectator.ReplaySystem do
  use GenServer
  alias MassiveMultiplayerArena.GameEngine.GameState
  require Logger

  @max_replay_size 10_000
  @cleanup_interval 60_000  # 1 minute
  @replay_retention_time 1_800_000  # 30 minutes

  defstruct [
    :game_id,
    :events,
    :start_time,
    :last_cleanup,
    :buffer_size
  ]

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def record_event(game_id, event) do
    GenServer.cast(via_tuple(game_id), {:record_event, event})
  end

  def get_replay(game_id, from_timestamp \\ nil) do
    GenServer.call(via_tuple(game_id), {:get_replay, from_timestamp})
  end

  def get_replay_stats(game_id) do
    GenServer.call(via_tuple(game_id), :get_stats)
  end

  def cleanup_old_events(game_id) do
    GenServer.cast(via_tuple(game_id), :cleanup_old_events)
  end

  @impl true
  def init(game_id) do
    schedule_cleanup()
    
    state = %__MODULE__{
      game_id: game_id,
      events: [],
      start_time: System.monotonic_time(:millisecond),
      last_cleanup: System.monotonic_time(:millisecond),
      buffer_size: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_event, event}, state) do
    timestamp = System.monotonic_time(:millisecond)
    timestamped_event = Map.put(event, :timestamp, timestamp)
    
    new_events = [timestamped_event | state.events]
    new_buffer_size = state.buffer_size + 1
    
    # Check if we need to trim the buffer
    {trimmed_events, final_buffer_size} = 
      if new_buffer_size > @max_replay_size do
        trimmed = Enum.take(new_events, @max_replay_size)
        {trimmed, @max_replay_size}
      else
        {new_events, new_buffer_size}
      end

    new_state = %{state | 
      events: trimmed_events,
      buffer_size: final_buffer_size
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:cleanup_old_events, state) do
    current_time = System.monotonic_time(:millisecond)
    cutoff_time = current_time - @replay_retention_time
    
    cleaned_events = Enum.filter(state.events, fn event ->
      event.timestamp > cutoff_time
    end)
    
    cleaned_count = length(cleaned_events)
    removed_count = state.buffer_size - cleaned_count
    
    if removed_count > 0 do
      Logger.info("Cleaned up #{removed_count} old replay events for game #{state.game_id}")
    end
    
    new_state = %{state |
      events: cleaned_events,
      buffer_size: cleaned_count,
      last_cleanup: current_time
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_replay, from_timestamp}, _from, state) do
    filtered_events = 
      case from_timestamp do
        nil -> Enum.reverse(state.events)
        timestamp -> 
          state.events
          |> Enum.filter(&(&1.timestamp >= timestamp))
          |> Enum.reverse()
      end

    replay_data = %{
      game_id: state.game_id,
      events: filtered_events,
      start_time: state.start_time,
      total_events: length(filtered_events)
    }

    {:reply, {:ok, replay_data}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    current_time = System.monotonic_time(:millisecond)
    
    stats = %{
      game_id: state.game_id,
      total_events: state.buffer_size,
      start_time: state.start_time,
      last_cleanup: state.last_cleanup,
      runtime: current_time - state.start_time,
      memory_usage: :erlang.process_info(self(), :memory)[:memory]
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup_timer, state) do
    send(self(), :cleanup_old_events)
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_old_events, state) do
    {:noreply, state} = handle_cast(:cleanup_old_events, state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Replay system for game #{state.game_id} shutting down with #{state.buffer_size} events")
    :ok
  end

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.ReplayRegistry, game_id}}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_timer, @cleanup_interval)
  end
end