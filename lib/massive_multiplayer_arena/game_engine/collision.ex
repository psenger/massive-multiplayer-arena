defmodule MassiveMultiplayerArena.GameEngine.Collision do
  @moduledoc """
  Handles collision detection between players and arena boundaries.
  """

  alias MassiveMultiplayerArena.GameEngine.Player

  @player_radius 10

  @doc """
  Checks if a position is within arena bounds.
  """
  @spec within_bounds?(%{x: float(), y: float()}, %{width: integer(), height: integer()}) :: boolean()
  def within_bounds?(%{x: x, y: y}, %{width: width, height: height}) do
    x >= @player_radius and x <= width - @player_radius and
    y >= @player_radius and y <= height - @player_radius
  end

  @doc """
  Clamps position to arena bounds.
  """
  @spec clamp_to_bounds(%{x: float(), y: float()}, %{width: integer(), height: integer()}) :: %{x: float(), y: float()}
  def clamp_to_bounds(%{x: x, y: y}, %{width: width, height: height}) do
    clamped_x = max(@player_radius, min(x, width - @player_radius))
    clamped_y = max(@player_radius, min(y, height - @player_radius))
    %{x: clamped_x, y: clamped_y}
  end

  @doc """
  Calculates distance between two positions.
  """
  @spec distance(%{x: float(), y: float()}, %{x: float(), y: float()}) :: float()
  def distance(%{x: x1, y: y1}, %{x: x2, y: y2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  @doc """
  Checks if two players are colliding.
  """
  @spec players_colliding?(Player.t(), Player.t()) :: boolean()
  def players_colliding?(%Player{position: pos1}, %Player{position: pos2}) do
    distance(pos1, pos2) <= @player_radius * 2
  end

  @doc """
  Checks if a player is within attack range of another player.
  """
  @spec within_attack_range?(Player.t(), Player.t(), float()) :: boolean()
  def within_attack_range?(%Player{position: pos1}, %Player{position: pos2}, range \\ 50.0) do
    distance(pos1, pos2) <= range
  end
end