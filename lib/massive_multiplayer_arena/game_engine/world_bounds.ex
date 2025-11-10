defmodule MassiveMultiplayerArena.GameEngine.WorldBounds do
  @moduledoc """
  Handles world boundaries and ensures entities stay within the game arena.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Physics}

  @type bounds :: %{
    min_x: float(),
    max_x: float(),
    min_y: float(),
    max_y: float()
  }

  @default_bounds %{
    min_x: 0.0,
    max_x: 1000.0,
    min_y: 0.0,
    max_y: 1000.0
  }

  @doc """
  Returns the default world bounds.
  """
  @spec default_bounds() :: bounds()
  def default_bounds, do: @default_bounds

  @doc """
  Checks if a position is within the world bounds.
  """
  @spec within_bounds?(Physics.position(), bounds()) :: boolean()
  def within_bounds?({x, y}, bounds) do
    x >= bounds.min_x and x <= bounds.max_x and
    y >= bounds.min_y and y <= bounds.max_y
  end

  @doc """
  Clamps a position to stay within world bounds.
  """
  @spec clamp_position(Physics.position(), bounds()) :: Physics.position()
  def clamp_position({x, y}, bounds) do
    clamped_x = max(bounds.min_x, min(bounds.max_x, x))
    clamped_y = max(bounds.min_y, min(bounds.max_y, y))
    {clamped_x, clamped_y}
  end

  @doc """
  Applies world bounds to a player, clamping their position if needed.
  """
  @spec apply_bounds(Player.t(), bounds()) :: Player.t()
  def apply_bounds(%Player{} = player, bounds \\ @default_bounds) do
    clamped_position = clamp_position(player.position, bounds)
    
    # If position was clamped, also zero out velocity in the clamped direction
    new_velocity = 
      if clamped_position != player.position do
        {pos_x, pos_y} = player.position
        {clamped_x, clamped_y} = clamped_position
        {vel_x, vel_y} = player.velocity
        
        new_vel_x = if clamped_x != pos_x, do: 0.0, else: vel_x
        new_vel_y = if clamped_y != pos_y, do: 0.0, else: vel_y
        
        {new_vel_x, new_vel_y}
      else
        player.velocity
      end
    
    %Player{player | position: clamped_position, velocity: new_velocity}
  end

  @doc """
  Calculates spawn points within the world bounds.
  """
  @spec random_spawn_point(bounds()) :: Physics.position()
  def random_spawn_point(bounds \\ @default_bounds) do
    # Add some padding from edges
    padding = 50.0
    
    x_range = bounds.max_x - bounds.min_x - (2 * padding)
    y_range = bounds.max_y - bounds.min_y - (2 * padding)
    
    x = bounds.min_x + padding + (:rand.uniform() * x_range)
    y = bounds.min_y + padding + (:rand.uniform() * y_range)
    
    {x, y}
  end
end