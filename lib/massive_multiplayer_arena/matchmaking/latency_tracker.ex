defmodule MassiveMultiplayerArena.Matchmaking.LatencyTracker do
  @moduledoc """
  Tracks and measures network latency for players to optimize matchmaking.
  """

  use GenServer
  alias MassiveMultiplayerArena.Matchmaking.SkillRating

  @ping_interval 5_000
  @latency_samples 10
  @max_latency_threshold 150

  defstruct [
    :player_id,
    :socket_pid,
    latency_samples: [],
    average_latency: 0,
    last_ping_time: nil,
    region: nil
  ]

  def start_link(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    socket_pid = Keyword.fetch!(opts, :socket_pid)
    GenServer.start_link(__MODULE__, {player_id, socket_pid}, name: via_tuple(player_id))
  end

  def get_latency(player_id) do
    GenServer.call(via_tuple(player_id), :get_latency)
  end

  def record_pong(player_id, ping_timestamp) do
    GenServer.cast(via_tuple(player_id), {:pong_received, ping_timestamp})
  end

  def get_region(player_id) do
    GenServer.call(via_tuple(player_id), :get_region)
  end

  def compatible_latency?(player1_id, player2_id) do
    latency1 = get_latency(player1_id)
    latency2 = get_latency(player2_id)
    
    abs(latency1 - latency2) <= 50
  end

  def init({player_id, socket_pid}) do
    Process.monitor(socket_pid)
    schedule_ping()
    
    state = %__MODULE__{
      player_id: player_id,
      socket_pid: socket_pid,
      region: determine_region()
    }
    
    {:ok, state}
  end

  def handle_call(:get_latency, _from, state) do
    {:reply, state.average_latency, state}
  end

  def handle_call(:get_region, _from, state) do
    {:reply, state.region, state}
  end

  def handle_cast({:pong_received, ping_timestamp}, state) do
    current_time = System.monotonic_time(:millisecond)
    latency = current_time - ping_timestamp
    
    new_samples = [latency | state.latency_samples]
                  |> Enum.take(@latency_samples)
    
    average_latency = Enum.sum(new_samples) / length(new_samples)
    
    new_state = %{state | 
      latency_samples: new_samples,
      average_latency: average_latency
    }
    
    {:noreply, new_state}
  end

  def handle_info(:send_ping, state) do
    ping_timestamp = System.monotonic_time(:millisecond)
    
    send(state.socket_pid, {:ping, ping_timestamp})
    
    schedule_ping()
    
    new_state = %{state | last_ping_time: ping_timestamp}
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  defp schedule_ping do
    Process.send_after(self(), :send_ping, @ping_interval)
  end

  defp determine_region do
    # Simplified region detection - in production this would use GeoIP
    [:na_east, :na_west, :eu_west, :asia_pacific]
    |> Enum.random()
  end

  defp via_tuple(player_id) do
    {:via, Registry, {MassiveMultiplayerArena.Registry, {:latency_tracker, player_id}}}
  end
end