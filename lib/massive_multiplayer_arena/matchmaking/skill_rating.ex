defmodule MassiveMultiplayerArena.Matchmaking.SkillRating do
  @moduledoc """
  Manages player skill ratings and calculations for matchmaking.
  Uses a modified ELO rating system with decay and volatility factors.
  """

  @default_rating 1200
  @k_factor 32
  @rating_floor 100
  @rating_ceiling 3000
  @decay_rate 0.02
  @decay_threshold_days 14

  defstruct [
    :player_id,
    :rating,
    :games_played,
    :wins,
    :losses,
    :last_updated,
    :volatility
  ]

  @type t :: %__MODULE__{
    player_id: String.t(),
    rating: integer(),
    games_played: integer(),
    wins: integer(),
    losses: integer(),
    last_updated: DateTime.t(),
    volatility: float()
  }

  @doc """
  Creates a new skill rating record for a player.
  """
  @spec new(String.t()) :: t()
  def new(player_id) do
    %__MODULE__{
      player_id: player_id,
      rating: @default_rating,
      games_played: 0,
      wins: 0,
      losses: 0,
      last_updated: DateTime.utc_now(),
      volatility: 0.5
    }
  end

  @doc """
  Updates a player's rating based on game outcome.
  """
  @spec update_rating(t(), t(), :win | :loss) :: {t(), t()}
  def update_rating(winner_rating, loser_rating, outcome) do
    winner_rating = apply_decay(winner_rating)
    loser_rating = apply_decay(loser_rating)

    expected_winner = expected_score(winner_rating.rating, loser_rating.rating)
    expected_loser = expected_score(loser_rating.rating, winner_rating.rating)

    case outcome do
      :win ->
        new_winner_rating = calculate_new_rating(winner_rating.rating, 1.0, expected_winner)
        new_loser_rating = calculate_new_rating(loser_rating.rating, 0.0, expected_loser)

        updated_winner = %{winner_rating |
          rating: new_winner_rating,
          games_played: winner_rating.games_played + 1,
          wins: winner_rating.wins + 1,
          last_updated: DateTime.utc_now(),
          volatility: update_volatility(winner_rating.volatility, 1.0, expected_winner)
        }

        updated_loser = %{loser_rating |
          rating: new_loser_rating,
          games_played: loser_rating.games_played + 1,
          losses: loser_rating.losses + 1,
          last_updated: DateTime.utc_now(),
          volatility: update_volatility(loser_rating.volatility, 0.0, expected_loser)
        }

        {updated_winner, updated_loser}
    end
  end

  @doc """
  Calculates the expected score between two players.
  """
  @spec expected_score(integer(), integer()) :: float()
  def expected_score(rating_a, rating_b) do
    1.0 / (1.0 + :math.pow(10, (rating_b - rating_a) / 400.0))
  end

  @doc """
  Applies rating decay for inactive players.
  """
  @spec apply_decay(t()) :: t()
  def apply_decay(%__MODULE__{last_updated: last_updated, rating: rating} = skill_rating) do
    days_since_update = DateTime.diff(DateTime.utc_now(), last_updated, :day)

    if days_since_update >= @decay_threshold_days do
      decay_amount = trunc((days_since_update - @decay_threshold_days) * @decay_rate * rating)
      new_rating = max(@rating_floor, rating - decay_amount)
      %{skill_rating | rating: new_rating}
    else
      skill_rating
    end
  end

  @doc """
  Determines if two players are within acceptable rating range for matching.
  """
  @spec rating_compatible?(t(), t(), integer()) :: boolean()
  def rating_compatible?(rating_a, rating_b, max_difference \\ 200) do
    abs(rating_a.rating - rating_b.rating) <= max_difference
  end

  @doc """
  Gets the skill tier for display purposes.
  """
  @spec get_tier(t()) :: atom()
  def get_tier(%__MODULE__{rating: rating}) do
    cond do
      rating >= 2400 -> :grandmaster
      rating >= 2000 -> :master
      rating >= 1700 -> :diamond
      rating >= 1400 -> :platinum
      rating >= 1100 -> :gold
      rating >= 800 -> :silver
      true -> :bronze
    end
  end

  # Private functions

  defp calculate_new_rating(current_rating, actual_score, expected_score) do
    new_rating = current_rating + @k_factor * (actual_score - expected_score)
    new_rating
    |> trunc()
    |> max(@rating_floor)
    |> min(@rating_ceiling)
  end

  defp update_volatility(current_volatility, actual_score, expected_score) do
    performance_diff = abs(actual_score - expected_score)
    volatility_change = performance_diff * 0.1
    
    new_volatility = current_volatility + volatility_change - 0.05
    max(0.1, min(1.0, new_volatility))
  end
end