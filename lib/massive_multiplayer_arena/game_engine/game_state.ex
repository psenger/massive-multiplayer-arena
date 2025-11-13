defmodule MassiveMultiplayerArena.GameEngine.GameState do
  @moduledoc """
  Manages the complete state of a game session including players,
  projectiles, power-ups, and game events.
  """

  alias MassiveMultiplayerArena.GameEngine.Player

  @max_players 16

  defstruct [
    :game_id,
    :status,
    :created_at,
    :updated_at,
    players: %{},
    projectiles: [],
    powerups: [],
    events: [],
    match_time: 0,
    score_limit: 50,
    time_limit: 600  # 10 minutes in seconds
  ]

  @type t :: %__MODULE__{
    game_id: String.t(),
    status: :waiting | :active | :finished,
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    players: %{String.t() => Player.t()},
    projectiles: list(),
    powerups: list(),
    events: list(),
    match_time: non_neg_integer(),
    score_limit: pos_integer(),
    time_limit: pos_integer()
  }

  def new(game_id \\ nil) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      game_id: game_id || generate_game_id(),
      status: :waiting,
      created_at: now,
      updated_at: now
    }
  end

  def add_player(%__MODULE__{players: players} = game_state, %Player{} = player) do
    cond do
      map_size(players) >= @max_players ->
        {:error, :game_full}
        
      Map.has_key?(players, player.id) ->
        {:error, :player_already_exists}
        
      true ->
        updated_players = Map.put(players, player.id, player)
        updated_state = %{game_state | 
          players: updated_players,
          updated_at: DateTime.utc_now()
        }
        
        # Start game if we have enough players
        if map_size(updated_players) >= 2 and game_state.status == :waiting do
          %{updated_state | status: :active}
        else
          updated_state
        end
    end
  end

  def remove_player(%__MODULE__{players: players} = game_state, player_id) do
    if Map.has_key?(players, player_id) do
      updated_players = Map.delete(players, player_id)
      updated_state = %{game_state | 
        players: updated_players,
        updated_at: DateTime.utc_now()
      }
      
      # End game if not enough players remain
      if map_size(updated_players) < 2 and game_state.status == :active do
        %{updated_state | status: :finished}
      else
        updated_state
      end
    else
      game_state
    end
  end

  def update_player_input(%__MODULE__{players: players} = game_state, player_id, input) do
    case Map.get(players, player_id) do
      nil -> 
        game_state
        
      player ->
        updated_player = Player.update_input(player, input)
        updated_players = Map.put(players, player_id, updated_player)
        
        %{game_state | 
          players: updated_players,
          updated_at: DateTime.utc_now()
        }
    end
  end

  def get_player(%__MODULE__{players: players}, player_id) do
    Map.get(players, player_id)
  end

  def list_players(%__MODULE__{players: players}) do
    Map.values(players)
  end

  def player_count(%__MODULE__{players: players}) do
    map_size(players)
  end

  def can_start_game?(%__MODULE__{players: players, status: status}) do
    status == :waiting and map_size(players) >= 2
  end

  def is_game_full?(%__MODULE__{players: players}) do
    map_size(players) >= @max_players
  end

  def is_game_empty?(%__MODULE__{players: players}) do
    map_size(players) == 0
  end

  def add_event(%__MODULE__{events: events} = game_state, event) do
    event_with_timestamp = Map.put(event, :timestamp, DateTime.utc_now())
    updated_events = [event_with_timestamp | Enum.take(events, 99)]  # Keep last 100 events
    
    %{game_state | 
      events: updated_events,
      updated_at: DateTime.utc_now()
    }
  end

  def update_match_time(%__MODULE__{} = game_state, delta_time) do
    new_time = game_state.match_time + delta_time
    
    updated_state = %{game_state | 
      match_time: new_time,
      updated_at: DateTime.utc_now()
    }
    
    # Check if time limit exceeded
    if new_time >= game_state.time_limit and game_state.status == :active do
      %{updated_state | status: :finished}
    else
      updated_state
    end
  end

  def check_win_condition(%__MODULE__{players: players, score_limit: score_limit} = game_state) do
    winner = players
             |> Map.values()
             |> Enum.find(&(&1.score >= score_limit))
    
    if winner and game_state.status == :active do
      game_state
      |> add_event(%{type: :game_won, player_id: winner.id, score: winner.score})
      |> Map.put(:status, :finished)
    else
      game_state
    end
  end

  def to_client_view(%__MODULE__{} = game_state) do
    %{
      game_id: game_state.game_id,
      status: game_state.status,
      players: Enum.map(game_state.players, fn {_id, player} -> 
        Player.to_client_view(player)
      end),
      match_time: game_state.match_time,
      score_limit: game_state.score_limit,
      time_limit: game_state.time_limit,
      recent_events: Enum.take(game_state.events, 10)
    }
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end