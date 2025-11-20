defmodule MassiveMultiplayerArena.GameEngine.Weapon do
  @moduledoc """
  Weapon system for handling different weapon types, damage calculation,
  and projectile mechanics in the arena.
  """

  defstruct [
    :id,
    :type,
    :damage,
    :range,
    :fire_rate,
    :projectile_speed,
    :projectile_size,
    :accuracy,
    :last_fired_at
  ]

  @weapon_types %{
    rifle: %{
      damage: 25,
      range: 800,
      fire_rate: 600,  # rounds per minute
      projectile_speed: 1200,
      projectile_size: 2,
      accuracy: 0.95
    },
    shotgun: %{
      damage: 60,
      range: 300,
      fire_rate: 120,
      projectile_speed: 800,
      projectile_size: 3,
      accuracy: 0.7
    },
    sniper: %{
      damage: 100,
      range: 1200,
      fire_rate: 60,
      projectile_speed: 1500,
      projectile_size: 1,
      accuracy: 0.98
    },
    pistol: %{
      damage: 20,
      range: 400,
      fire_rate: 300,
      projectile_speed: 900,
      projectile_size: 2,
      accuracy: 0.85
    }
  }

  @doc """
  Creates a new weapon of the specified type.
  """
  def new(type) when is_atom(type) do
    case Map.get(@weapon_types, type) do
      nil -> {:error, :invalid_weapon_type}
      stats -> 
        {:ok, %__MODULE__{
          id: generate_id(),
          type: type,
          damage: stats.damage,
          range: stats.range,
          fire_rate: stats.fire_rate,
          projectile_speed: stats.projectile_speed,
          projectile_size: stats.projectile_size,
          accuracy: stats.accuracy,
          last_fired_at: 0
        }}
    end
  end

  @doc """
  Checks if weapon can fire based on fire rate cooldown.
  """
  def can_fire?(weapon, current_time) do
    fire_interval = 60_000 / weapon.fire_rate  # milliseconds between shots
    current_time - weapon.last_fired_at >= fire_interval
  end

  @doc """
  Creates a projectile when weapon is fired.
  """
  def fire(weapon, shooter_pos, target_pos, current_time) do
    if can_fire?(weapon, current_time) do
      projectile = create_projectile(weapon, shooter_pos, target_pos, current_time)
      updated_weapon = %{weapon | last_fired_at: current_time}
      {:ok, projectile, updated_weapon}
    else
      {:error, :weapon_on_cooldown}
    end
  end

  @doc """
  Calculates damage dealt by weapon, considering distance and accuracy.
  """
  def calculate_damage(weapon, distance) do
    base_damage = weapon.damage
    
    # Damage falloff based on range
    damage_multiplier = cond do
      distance <= weapon.range * 0.3 -> 1.0  # Full damage at close range
      distance <= weapon.range * 0.7 -> 0.8  # 80% damage at medium range
      distance <= weapon.range -> 0.5        # 50% damage at max range
      true -> 0                               # No damage beyond range
    end
    
    # Apply accuracy as damage variation
    accuracy_factor = :rand.uniform() * (weapon.accuracy * 0.2) + (1.0 - weapon.accuracy * 0.1)
    
    round(base_damage * damage_multiplier * accuracy_factor)
  end

  defp create_projectile(weapon, {x1, y1}, {x2, y2}, timestamp) do
    # Calculate direction vector
    dx = x2 - x1
    dy = y2 - y1
    distance = :math.sqrt(dx * dx + dy * dy)
    
    # Normalize direction
    {norm_dx, norm_dy} = if distance > 0 do
      {dx / distance, dy / distance}
    else
      {1.0, 0.0}
    end
    
    # Apply accuracy spread
    spread = (1.0 - weapon.accuracy) * 0.1
    angle_offset = (:rand.uniform() - 0.5) * spread
    
    cos_offset = :math.cos(angle_offset)
    sin_offset = :math.sin(angle_offset)
    
    final_dx = norm_dx * cos_offset - norm_dy * sin_offset
    final_dy = norm_dx * sin_offset + norm_dy * cos_offset
    
    %{
      id: generate_id(),
      weapon_type: weapon.type,
      position: {x1, y1},
      velocity: {
        final_dx * weapon.projectile_speed,
        final_dy * weapon.projectile_speed
      },
      size: weapon.projectile_size,
      damage: weapon.damage,
      range: weapon.range,
      distance_traveled: 0,
      created_at: timestamp
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end