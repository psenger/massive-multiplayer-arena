defmodule MassiveMultiplayerArena.GameEngine.Player do
  @moduledoc """
  Represents a player in the game with position, health, and combat stats.
  """

  defstruct [
    :id,
    :username,
    :position,
    :health,
    :max_health,
    :speed,
    :damage,
    :last_action,
    :connected_at,
    :skill_rating
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    username: String.t(),
    position: %{x: float(), y: float()},
    health: integer(),
    max_health: integer(),
    speed: float(),
    damage: integer(),
    last_action: DateTime.t() | nil,
    connected_at: DateTime.t(),
    skill_rating: integer()
  }

  @doc """
  Creates a new player with default stats.
  """
  @spec new(String.t(), String.t(), integer()) :: t()
  def new(id, username, skill_rating \\ 1000) do
    %__MODULE__{
      id: id,
      username: username,
      position: %{x: 0.0, y: 0.0},
      health: 100,
      max_health: 100,
      speed: 5.0,
      damage: 20,
      last_action: nil,
      connected_at: DateTime.utc_now(),
      skill_rating: skill_rating
    }
  end

  @doc """
  Updates player position.
  """
  @spec move(t(), %{x: float(), y: float()}) :: t()
  def move(%__MODULE__{} = player, new_position) do
    %{player | position: new_position, last_action: DateTime.utc_now()}
  end

  @doc """
  Applies damage to player and returns updated player.
  """
  @spec take_damage(t(), integer()) :: t()
  def take_damage(%__MODULE__{health: health} = player, damage) do
    new_health = max(0, health - damage)
    %{player | health: new_health, last_action: DateTime.utc_now()}
  end

  @doc """
  Checks if player is alive.
  """
  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{health: health}), do: health > 0
end