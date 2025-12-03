defmodule MassiveMultiplayerArena.GameEngine.Physics do
  @moduledoc """
  Physics engine for handling movement, velocity, and forces.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, WorldBounds}

  @gravity 9.8
  @friction 0.95
  @max_velocity 500.0
  @epsilon 0.001

  @doc """
  Updates player position based on velocity and physics.
  """
  def update_position(%Player{} = player, delta_time) do
    try do
      # Apply velocity with bounds checking
      new_x = player.position.x + (player.velocity.x * delta_time)
      new_y = player.position.y + (player.velocity.y * delta_time)

      # Clamp position to world bounds to prevent overflow
      clamped_position = %{
        x: clamp_coordinate(new_x, WorldBounds.min_x(), WorldBounds.max_x()),
        y: clamp_coordinate(new_y, WorldBounds.min_y(), WorldBounds.max_y())
      }

      # Update player with new position
      %{player | position: clamped_position}
    rescue
      ArithmeticError ->
        # Reset to safe position on arithmetic overflow
        %{player | position: %{x: 0.0, y: 0.0}, velocity: %{x: 0.0, y: 0.0}}
    end
  end

  @doc """
  Applies force to player velocity.
  """
  def apply_force(%Player{} = player, force_x, force_y, delta_time) do
    # Calculate new velocity with force application
    new_vel_x = player.velocity.x + (force_x * delta_time)
    new_vel_y = player.velocity.y + (force_y * delta_time)

    # Apply friction and clamp velocity
    final_vel_x = clamp_velocity(new_vel_x * @friction)
    final_vel_y = clamp_velocity(new_vel_y * @friction)

    # Zero out very small velocities to prevent floating point drift
    velocity = %{
      x: if(abs(final_vel_x) < @epsilon, do: 0.0, else: final_vel_x),
      y: if(abs(final_vel_y) < @epsilon, do: 0.0, else: final_vel_y)
    }

    %{player | velocity: velocity}
  end

  @doc """
  Calculates impulse from collision.
  """
  def calculate_collision_impulse(player1, player2, collision_normal) do
    relative_velocity = %{
      x: player1.velocity.x - player2.velocity.x,
      y: player1.velocity.y - player2.velocity.y
    }

    # Calculate relative velocity along collision normal
    velocity_along_normal = 
      relative_velocity.x * collision_normal.x + relative_velocity.y * collision_normal.y

    # Don't resolve if velocities are separating
    if velocity_along_normal > 0 do
      {%{x: 0.0, y: 0.0}, %{x: 0.0, y: 0.0}}
    else
      # Calculate restitution (bounciness)
      restitution = min(player1.restitution || 0.6, player2.restitution || 0.6)
      
      # Calculate impulse scalar
      impulse_scalar = -(1 + restitution) * velocity_along_normal / 2
      
      # Apply impulse
      impulse = %{
        x: impulse_scalar * collision_normal.x,
        y: impulse_scalar * collision_normal.y
      }

      {impulse, %{x: -impulse.x, y: -impulse.y}}
    end
  end

  defp clamp_coordinate(value, min_val, max_val) when is_number(value) and is_number(min_val) and is_number(max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  defp clamp_coordinate(_value, min_val, _max_val), do: min_val

  defp clamp_velocity(velocity) when is_number(velocity) do
    velocity
    |> max(-@max_velocity)
    |> min(@max_velocity)
  end

  defp clamp_velocity(_velocity), do: 0.0

  @doc """
  Updates positions for all players in the game state.
  """
  def update_positions(game_state, delta_time) do
    updated_players = game_state.players
    |> Enum.map(fn {id, player} ->
      updated_player = update_position(player, delta_time)
      {id, updated_player}
    end)
    |> Map.new()

    %{game_state | players: updated_players}
  end
end