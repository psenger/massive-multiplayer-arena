defmodule MassiveMultiplayerArena.Matchmaking.Matchmaker do
  @moduledoc """
  Dynamic matchmaking system that pairs players based on skill rating and latency.
  Uses ETS for fast lookups and maintains separate queues for different game modes.
  """

  use GenServer
  require Logger

  alias MassiveMultiplayerArena.GameEngine.GameSupervisor

  @queue_table :matchmaking_queue
  @match_interval 1000  # Check for matches every second
  @skill_tolerance 100  # Initial skill rating tolerance
  @max_skill_tolerance 300  # Maximum skill tolerance after waiting
  @latency_threshold 150  # Maximum acceptable latency difference (ms)

  defstruct [
    :queue_table,
    :active_matches,
    :match_timer
  ]

  ## Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def join_queue(player_id, player_data) do
    GenServer.call(__MODULE__, {:join_queue, player_id, player_data})
  end

  def leave_queue(player_id) do
    GenServer.call(__MODULE__, {:leave_queue, player_id})
  end

  def get_queue_status(player_id) do
    GenServer.call(__MODULE__, {:queue_status, player_id})
  end

  def get_queue_stats do
    GenServer.call(__MODULE__, :queue_stats)
  end

  ## Server Implementation

  @impl true
  def init(_) do
    # Create ETS table for fast queue operations
    :ets.new(@queue_table, [:set, :named_table, :public])
    
    state = %__MODULE__{
      queue_table: @queue_table,
      active_matches: %{},
      match_timer: schedule_matchmaking()
    }
    
    Logger.info("Matchmaker started")
    {:ok, state}
  end

  @impl true
  def handle_call({:join_queue, player_id, player_data}, _from, state) do
    queue_entry = %{
      player_id: player_id,
      skill_rating: player_data.skill_rating,
      latency: player_data.latency,
      game_mode: player_data.game_mode,
      joined_at: System.monotonic_time(:millisecond),
      region: player_data.region
    }
    
    :ets.insert(@queue_table, {player_id, queue_entry})
    
    Logger.info("Player #{player_id} joined matchmaking queue")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:leave_queue, player_id}, _from, state) do
    :ets.delete(@queue_table, player_id)
    Logger.info("Player #{player_id} left matchmaking queue")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:queue_status, player_id}, _from, state) do
    case :ets.lookup(@queue_table, player_id) do
      [{^player_id, entry}] ->
        wait_time = System.monotonic_time(:millisecond) - entry.joined_at
        {:reply, {:in_queue, wait_time}, state}
      [] ->
        {:reply, :not_in_queue, state}
    end
  end

  @impl true
  def handle_call(:queue_stats, _from, state) do
    queue_size = :ets.info(@queue_table, :size)
    active_matches = map_size(state.active_matches)
    
    stats = %{
      players_in_queue: queue_size,
      active_matches: active_matches,
      average_wait_time: calculate_average_wait_time()
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:find_matches, state) do
    new_matches = find_and_create_matches()
    
    updated_state = Enum.reduce(new_matches, state, fn {game_id, players}, acc ->
      # Remove matched players from queue
      Enum.each(players, fn player_id -> 
        :ets.delete(@queue_table, player_id)
      end)
      
      # Track active match
      Map.put(acc, :active_matches, Map.put(acc.active_matches, game_id, players))
    end)
    
    # Schedule next matchmaking cycle
    timer = schedule_matchmaking()
    
    {:noreply, %{updated_state | match_timer: timer}}
  end

  ## Private Functions

  defp find_and_create_matches do
    @queue_table
    |> :ets.tab2list()
    |> Enum.group_by(fn {_, entry} -> {entry.game_mode, entry.region} end)
    |> Enum.flat_map(fn {_mode_region, players} -> 
        create_matches_for_group(players)
    end)
  end

  defp create_matches_for_group(players) do
    players
    |> Enum.sort_by(fn {_, entry} -> entry.skill_rating end)
    |> find_compatible_matches([])
  end

  defp find_compatible_matches([], matches), do: matches
  defp find_compatible_matches([player | rest], matches) when length(rest) < 1 do
    matches  # Need at least 2 players
  end
  defp find_compatible_matches([{player_id, entry} | rest], matches) do
    current_time = System.monotonic_time(:millisecond)
    wait_time = current_time - entry.joined_at
    
    # Increase skill tolerance based on wait time
    skill_tolerance = min(@skill_tolerance + (wait_time / 1000 * 10), @max_skill_tolerance)
    
    compatible_players = find_compatible_players(entry, rest, skill_tolerance, [player_id])
    
    if length(compatible_players) >= 2 do
      game_id = generate_game_id()
      
      # Start new game
      {:ok, _pid} = GameSupervisor.start_game(game_id)
      
      # Notify players
      Enum.each(compatible_players, fn pid ->
        notify_match_found(pid, game_id)
      end)
      
      remaining_players = Enum.reject(rest, fn {pid, _} -> 
        pid in compatible_players
      end)
      
      [{game_id, compatible_players} | find_compatible_matches(remaining_players, matches)]
    else
      find_compatible_matches(rest, matches)
    end
  end

  defp find_compatible_players(_, [], _, matched), do: matched
  defp find_compatible_players(base_entry, [{player_id, entry} | rest], tolerance, matched) do
    skill_diff = abs(base_entry.skill_rating - entry.skill_rating)
    latency_diff = abs(base_entry.latency - entry.latency)
    
    if skill_diff <= tolerance and latency_diff <= @latency_threshold do
      find_compatible_players(base_entry, rest, tolerance, [player_id | matched])
    else
      find_compatible_players(base_entry, rest, tolerance, matched)
    end
  end

  defp schedule_matchmaking do
    Process.send_after(self(), :find_matches, @match_interval)
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp notify_match_found(player_id, game_id) do
    Phoenix.PubSub.broadcast(
      MassiveMultiplayerArena.PubSub,
      "player:#{player_id}",
      {:match_found, game_id}
    )
  end

  defp calculate_average_wait_time do
    current_time = System.monotonic_time(:millisecond)
    
    wait_times = @queue_table
    |> :ets.tab2list()
    |> Enum.map(fn {_, entry} -> current_time - entry.joined_at end)
    
    if length(wait_times) > 0 do
      Enum.sum(wait_times) / length(wait_times)
    else
      0
    end
  end
end