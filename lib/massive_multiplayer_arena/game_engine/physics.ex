defmodule MassiveMultiplayerArena.GameEngine.Physics do
  @moduledoc """
  Physics engine for handling movement, velocity, and basic physics calculations
  in the game world.
  """

  alias MassiveMultiplayerArena.GameEngine.Player

  @type vector :: {float(), float()}
  @type position :: vector()
  @type velocity :: vector()

  @doc """
  Updates player position based on velocity and time delta.
  """
  @spec update_position(Player.t(), float()) :: Player.t()
  def update_position(%Player{} = player, delta_time) do
    {pos_x, pos_y} = player.position
    {vel_x, vel_y} = player.velocity

    new_x = pos_x + vel_x * delta_time
    new_y = pos_y + vel_y * delta_time

    %Player{player | position: {new_x, new_y}}
  end

  @doc """
  Calculates distance between two positions.
  """
  @spec distance(position(), position()) :: float()
  def distance({x1, y1}, {x2, y2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  @doc """
  Normalizes a vector to unit length.
  """
  @spec normalize(vector()) :: vector()
  def normalize({x, y}) do
    magnitude = :math.sqrt(x * x + y * y)
    if magnitude > 0 do
      {x / magnitude, y / magnitude}
    else
      {0.0, 0.0}
    end
  end

  @doc """
  Applies friction to velocity, reducing it over time.
  """
  @spec apply_friction(velocity(), float(), float()) :: velocity()
  def apply_friction({vel_x, vel_y}, friction_coefficient, delta_time) do
    friction_factor = 1.0 - (friction_coefficient * delta_time)
    friction_factor = max(0.0, friction_factor)
    {vel_x * friction_factor, vel_y * friction_factor}
  end

  @doc """
  Calculates velocity needed to move towards a target position.
  """
  @spec velocity_towards(position(), position(), float()) :: velocity()
  def velocity_towards(from_pos, to_pos, speed) do
    {dx, dy} = vector_subtract(to_pos, from_pos)
    {norm_x, norm_y} = normalize({dx, dy})
    {norm_x * speed, norm_y * speed}
  end

  @doc """
  Subtracts one vector from another.
  """
  @spec vector_subtract(vector(), vector()) :: vector()
  def vector_subtract({x1, y1}, {x2, y2}) do
    {x1 - x2, y1 - y2}
  end

  @doc """
  Adds two vectors together.
  """
  @spec vector_add(vector(), vector()) :: vector()
  def vector_add({x1, y1}, {x2, y2}) do
    {x1 + x2, y1 + y2}
  end

  @doc """
  Multiplies a vector by a scalar value.
  """
  @spec vector_multiply(vector(), float()) :: vector()
  def vector_multiply({x, y}, scalar) do
    {x * scalar, y * scalar}
  end
end