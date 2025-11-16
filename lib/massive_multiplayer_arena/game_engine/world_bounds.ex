defmodule MassiveMultiplayerArena.GameEngine.WorldBounds do
  @moduledoc """
  Manages world boundaries and position validation for the game arena.
  """

  @world_width 2000
  @world_height 2000
  @player_radius 25

  @doc """
  Checks if a position is within the world boundaries.
  """
  def within_bounds?(position) when is_map(position) do
    return false if not Map.has_key?(position, :x) or not Map.has_key?(position, :y)
    return false if not is_number(position.x) or not is_number(position.y)
    
    position.x >= @player_radius and
    position.x <= (@world_width - @player_radius) and
    position.y >= @player_radius and
    position.y <= (@world_height - @player_radius)
  end

  def within_bounds?(_), do: false

  @doc """
  Clamps a position to stay within world boundaries.
  """
  def clamp_position(position) when is_map(position) do
    return %{x: 0, y: 0} if not Map.has_key?(position, :x) or not Map.has_key?(position, :y)
    return %{x: 0, y: 0} if not is_number(position.x) or not is_number(position.y)
    
    x = position.x
    |> max(@player_radius)
    |> min(@world_width - @player_radius)
    
    y = position.y
    |> max(@player_radius)
    |> min(@world_height - @player_radius)
    
    %{x: x, y: y}
  end

  def clamp_position(_), do: %{x: @player_radius, y: @player_radius}

  @doc """
  Gets the world dimensions.
  """
  def get_dimensions do
    %{width: @world_width, height: @world_height}
  end

  @doc """
  Generates a random position within the world boundaries.
  """
  def random_position do
    x = @player_radius + :rand.uniform(@world_width - (2 * @player_radius))
    y = @player_radius + :rand.uniform(@world_height - (2 * @player_radius))
    %{x: x, y: y}
  end

  @doc """
  Calculates the distance from a position to the nearest boundary.
  """
  def distance_to_boundary(position) when is_map(position) do
    return 0 if not Map.has_key?(position, :x) or not Map.has_key?(position, :y)
    return 0 if not is_number(position.x) or not is_number(position.y)
    
    distances = [
      position.x - @player_radius,  # left boundary
      (@world_width - @player_radius) - position.x,  # right boundary
      position.y - @player_radius,  # top boundary
      (@world_height - @player_radius) - position.y  # bottom boundary
    ]
    
    Enum.min(distances)
  end

  def distance_to_boundary(_), do: 0
end