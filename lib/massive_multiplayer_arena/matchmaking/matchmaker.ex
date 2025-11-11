defmodule MassiveMultiplayerArena.Matchmaking.Matchmaker do
  @moduledoc """
  Handles player matchmaking based on skill rating and latency.
  Maintains queues and creates balanced matches.
  """

  use GenServer
  alias MassiveMultiplayerArena.Matchmaking.SkillRating
  require Logger

  @match_timeout 30_000
  @max_skill_difference 200
  @max_latency_difference 50

  defstruct [
    :queue,
    :pending_matches,
    :skill_ratings
  ]

  @type queue_entry :: %{
    player_id: String.t(),
    skill_rating: SkillRating.t(),
    latency: integer(),
    joined_at: DateTime.t()
  }

  @type pending_match :: %{
    match_id: String.t(),
    players: [String.t()],
    created_at: DateTime.t()
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_matchmaking_tick()
    
    state = %__MODULE__{
      queue: [],
      pending_matches: %{},
      skill_ratings: %{}
    }
    
    {:ok, state}
  end

  @doc """
  Adds a player to the matchmaking queue.
  """
  @spec join_queue(String.t(), integer()) :: :ok | {:error, term()}
  def join_queue(player_id, latency) do
    GenServer.call(__MODULE__, {:join_queue, player_id, latency})
  end

  @doc """
  Removes a player from the matchmaking queue.
  """
  @spec leave_queue(String.t()) :: :ok
  def leave_queue(player_id) do
    GenServer.call(__MODULE__, {:leave_queue, player_id})
  end

  @doc """
  Gets current queue status for a player.
  """
  @spec queue_status(String.t()) :: {:ok, map()} | {:error, :not_in_queue}
  def queue_status(player_id) do
    GenServer.call(__MODULE__, {:queue_status, player_id})
  end

  @doc """
  Updates a player's skill rating after a game.
  """
  @spec update_player_rating(String.t(), String.t(), :win | :loss) :: :ok
  def update_player_rating(winner_id, loser_id, outcome) do
    GenServer.cast(__MODULE__, {:update_rating, winner_id, loser_id, outcome})
  end

  @impl true
  def handle_call({:join_queue, player_id, latency}, _from, state) do
    case get_or_create_skill_rating(player_id, state) do
      {skill_rating, new_state} ->
        queue_entry = %{
          player_id: player_id,
          skill_rating: skill_rating,
          latency: latency,
          joined_at: DateTime.utc_now()
        }
        
        updated_queue = [queue_entry | new_state.queue]
        updated_state = %{new_state | queue: updated_queue}
        
        Logger.info("Player #{player_id} joined matchmaking queue (rating: #{skill_rating.rating})")
        {:reply, :ok, updated_state}
    end
  end

  @impl true
  def handle_call({:leave_queue, player_id}, _from, state) do
    updated_queue = Enum.reject(state.queue, &(&1.player_id == player_id))
    updated_state = %{state | queue: updated_queue}
    
    Logger.info("Player #{player_id} left matchmaking queue")
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:queue_status, player_id}, _from, state) do
    case Enum.find(state.queue, &(&1.player_id == player_id)) do
      nil ->
        {:reply, {:error, :not_in_queue}, state}
      queue_entry ->
        status = %{
          position: get_queue_position(player_id, state.queue),
          wait_time: DateTime.diff(DateTime.utc_now(), queue_entry.joined_at),
          estimated_wait: estimate_wait_time(queue_entry, state.queue)
        }
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_cast({:update_rating, winner_id, loser_id, outcome}, state) do
    {winner_rating, state} = get_or_create_skill_rating(winner_id, state)
    {loser_rating, state} = get_or_create_skill_rating(loser_id, state)
    
    {updated_winner, updated_loser} = SkillRating.update_rating(winner_rating, loser_rating, outcome)
    
    updated_ratings = state.skill_ratings
    |> Map.put(winner_id, updated_winner)
    |> Map.put(loser_id, updated_loser)
    
    updated_state = %{state | skill_ratings: updated_ratings}
    
    Logger.info("Updated ratings - Winner: #{updated_winner.rating}, Loser: #{updated_loser.rating}")
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:matchmaking_tick, state) do
    updated_state = process_matchmaking(state)
    schedule_matchmaking_tick()
    {:noreply, updated_state}
  end

  # Private functions

  defp get_or_create_skill_rating(player_id, state) do
    case Map.get(state.skill_ratings, player_id) do
      nil ->
        skill_rating = SkillRating.new(player_id)
        updated_ratings = Map.put(state.skill_ratings, player_id, skill_rating)
        updated_state = %{state | skill_ratings: updated_ratings}
        {skill_rating, updated_state}
      skill_rating ->
        {skill_rating, state}
    end
  end

  defp process_matchmaking(state) do
    state.queue
    |> find_matches()
    |> create_matches(state)
  end

  defp find_matches(queue) do
    queue
    |> Enum.sort_by(& &1.joined_at)
    |> find_compatible_pairs([])
  end

  defp find_compatible_pairs([], matches), do: matches
  defp find_compatible_pairs([player | rest], matches) do
    case find_opponent(player, rest) do
      {opponent, remaining_players} ->
        match = {player, opponent}
        find_compatible_pairs(remaining_players, [match | matches])
      nil ->
        find_compatible_pairs(rest, matches)
    end
  end

  defp find_opponent(player, candidates) do
    Enum.find_value(candidates, fn candidate ->
      if players_compatible?(player, candidate) do
        remaining = List.delete(candidates, candidate)
        {candidate, remaining}
      end
    end)
  end

  defp players_compatible?(player1, player2) do
    skill_compatible = SkillRating.rating_compatible?(
      player1.skill_rating,
      player2.skill_rating,
      @max_skill_difference
    )
    
    latency_compatible = abs(player1.latency - player2.latency) <= @max_latency_difference
    
    skill_compatible and latency_compatible
  end

  defp create_matches(matches, state) do
    {new_pending_matches, updated_queue} = 
      Enum.reduce(matches, {state.pending_matches, state.queue}, fn {player1, player2}, {pending, queue} ->
        match_id = generate_match_id()
        
        match = %{
          match_id: match_id,
          players: [player1.player_id, player2.player_id],
          created_at: DateTime.utc_now()
        }
        
        # Remove matched players from queue
        updated_queue = Enum.reject(queue, fn entry ->
          entry.player_id in [player1.player_id, player2.player_id]
        end)
        
        # Notify game engine to create match
        notify_game_engine(match)
        
        Logger.info("Created match #{match_id} for players #{player1.player_id} vs #{player2.player_id}")
        
        {Map.put(pending, match_id, match), updated_queue}
      end)
    
    %{state | pending_matches: new_pending_matches, queue: updated_queue}
  end

  defp get_queue_position(player_id, queue) do
    queue
    |> Enum.sort_by(& &1.joined_at)
    |> Enum.find_index(&(&1.player_id == player_id))
    |> case do
      nil -> 0
      index -> index + 1
    end
  end

  defp estimate_wait_time(_queue_entry, queue) do
    # Simple estimation based on queue length
    length(queue) * 15 # 15 seconds per player ahead
  end

  defp generate_match_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp notify_game_engine(match) do
    # TODO: Send match creation request to game engine
    # This will be implemented when we add the game engine communication
    :ok
  end

  defp schedule_matchmaking_tick do
    Process.send_after(self(), :matchmaking_tick, 5_000)
  end
end