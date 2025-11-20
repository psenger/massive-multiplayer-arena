defmodule MassiveMultiplayerArena.GameEngine.Projectile do
  @moduledoc """
  Handles projectile physics, movement, and collision detection
  for weapons in the multiplayer arena.
  """

  alias MassiveMultiplayerArena.GameEngine.{Collision, WorldBounds}

  defstruct [
    :id,
    :weapon_type,
    :position,
    :velocity,
    :size,
    :damage,
    :range,
    :distance_traveled,
    :created_at,
    :owner_id
  ]

  @doc """
  Updates projectile position based on velocity and delta time.
  Returns {:ok, updated_projectile} or {:expired, projectile} if out of range.
  """
  def update(projectile, delta_time) do
    {vx, vy} = projectile.velocity
    {x, y} = projectile.position
    
    # Calculate movement based on delta time (in seconds)
    dt = delta_time / 1000.0
    new_x = x + vx * dt
    new_y = y + vy * dt
    
    # Calculate distance traveled this frame
    distance_delta = :math.sqrt((vx * dt) * (vx * dt) + (vy * dt) * (vy * dt))
    new_distance = projectile.distance_traveled + distance_delta
    
    updated_projectile = %{projectile |
      position: {new_x, new_y},
      distance_traveled: new_distance
    }
    
    cond do
      new_distance >= projectile.range -> {:expired, updated_projectile}
      WorldBounds.out_of_bounds?({new_x, new_y}) -> {:out_of_bounds, updated_projectile}
      true -> {:ok, updated_projectile}
    end
  end

  @doc """
  Checks if projectile collides with a player.
  Returns {:hit, damage} or :miss.
  """
  def check_player_collision(projectile, player) do
    # Don't hit the shooter
    if projectile.owner_id == player.id do
      :miss
    else
      distance = Collision.distance(projectile.position, player.position)
      collision_threshold = projectile.size + player.size
      
      if distance <= collision_threshold do
        {:hit, calculate_impact_damage(projectile, distance)}
      else
        :miss
      end
    end
  end

  @doc """
  Checks if projectile collides with world obstacles.
  """
  def check_world_collision(projectile, obstacles) when is_list(obstacles) do
    Enum.find_value(obstacles, :no_collision, fn obstacle ->
      if collides_with_obstacle?(projectile, obstacle) do
        {:collision, obstacle}
      else
        false
      end
    end)
  end

  @doc """
  Updates multiple projectiles in a batch, removing expired ones.
  """
  def update_batch(projectiles, delta_time, players, obstacles \\ []) do
    {active, expired, hits} = 
      Enum.reduce(projectiles, {[], [], []}, fn projectile, {active, expired, hits} ->
        case update(projectile, delta_time) do
          {:ok, updated} ->
            # Check for collisions
            case check_collisions(updated, players, obstacles) do
              {:hit, player_id, damage} ->
                hit = %{projectile_id: updated.id, player_id: player_id, damage: damage}
                {active, expired, [hit | hits]}
              :no_collision ->
                {[updated | active], expired, hits}
              {:obstacle_hit, _obstacle} ->
                {active, [updated | expired], hits}
            end
          
          {_status, expired_projectile} ->
            {active, [expired_projectile | expired], hits}
        end
      end)
    
    %{
      active: Enum.reverse(active),
      expired: Enum.reverse(expired),
      hits: Enum.reverse(hits)
    }
  end

  defp check_collisions(projectile, players, obstacles) do
    # Check player collisions first
    case Enum.find_value(players, fn player ->
      case check_player_collision(projectile, player) do
        {:hit, damage} -> {player.id, damage}
        :miss -> false
      end
    end) do
      {player_id, damage} -> {:hit, player_id, damage}
      nil ->
        # Check obstacle collisions
        case check_world_collision(projectile, obstacles) do
          {:collision, obstacle} -> {:obstacle_hit, obstacle}
          :no_collision -> :no_collision
        end
    end
  end

  defp calculate_impact_damage(projectile, _collision_distance) do
    # For now, return full damage. Could implement distance-based damage reduction
    projectile.damage
  end

  defp collides_with_obstacle?(projectile, obstacle) do
    # Simple rectangular obstacle collision
    {px, py} = projectile.position
    size = projectile.size
    
    case obstacle do
      %{x: ox, y: oy, width: w, height: h} ->
        px + size >= ox and px - size <= ox + w and
        py + size >= oy and py - size <= oy + h
      _ -> false
    end
  end
end