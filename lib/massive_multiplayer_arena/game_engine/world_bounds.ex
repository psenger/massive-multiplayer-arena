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
    if not Map.has_key?(position, :x) or not Map.has_key?(position, :y) do
      false
    else
      if not is_number(position.x) or not is_number(position.y) do
        false
      else
        position.x >= @player_radius and
        position.x <= (@world_width - @player_radius) and
        position.y >= @player_radius and
        position.y <= (@world_height - @player_radius)
      end
    end
  end

  def within_bounds?(_), do: false

  @doc """
  Clamps a position to stay within world boundaries.
  """
  def clamp_position(position) when is_map(position) do
    if not Map.has_key?(position, :x) or not Map.has_key?(position, :y) do
      %{x: 0, y: 0}
    else
      if not is_number(position.x) or not is_number(position.y) do
        %{x: 0, y: 0}
      else
        x = position.x
        |> max(@player_radius)
        |> min(@world_width - @player_radius)

        y = position.y
        |> max(@player_radius)
        |> min(@world_height - @player_radius)

        %{x: x, y: y}
      end
    end
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
    if not Map.has_key?(position, :x) or not Map.has_key?(position, :y) do
      0
    else
      if not is_number(position.x) or not is_number(position.y) do
        0
      else
        distances = [
          position.x - @player_radius,
          (@world_width - @player_radius) - position.x,
          position.y - @player_radius,
          (@world_height - @player_radius) - position.y
        ]

        Enum.min(distances)
      end
    end
  end

  def distance_to_boundary(_), do: 0

  @doc """
  Returns the minimum x coordinate (with player radius buffer).
  """
  def min_x, do: @player_radius

  @doc """
  Returns the maximum x coordinate (with player radius buffer).
  """
  def max_x, do: @world_width - @player_radius

  @doc """
  Returns the minimum y coordinate (with player radius buffer).
  """
  def min_y, do: @player_radius

  @doc """
  Returns the maximum y coordinate (with player radius buffer).
  """
  def max_y, do: @world_height - @player_radius

  @doc """
  Checks if a position tuple {x, y} is out of bounds.
  """
  def out_of_bounds?({x, y}) when is_number(x) and is_number(y) do
    x < @player_radius or x > (@world_width - @player_radius) or
    y < @player_radius or y > (@world_height - @player_radius)
  end

  def out_of_bounds?(_), do: true

  @doc """
  Enforces world bounds on all players in the game state.
  """
  def enforce_bounds(game_state) do
    updated_players = game_state.players
    |> Enum.map(fn {id, player} ->
      clamped_position = clamp_position(player.position)
      {id, %{player | position: clamped_position}}
    end)
    |> Map.new()

    %{game_state | players: updated_players}
  end
end