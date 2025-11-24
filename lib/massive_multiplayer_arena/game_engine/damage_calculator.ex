defmodule MassiveMultiplayerArena.GameEngine.DamageCalculator do
  @moduledoc """
  Handles damage calculations including base damage, weapon modifiers,
  critical hits, and damage reduction from power-ups.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Weapon, PowerUp}

  @critical_hit_chance 0.15
  @critical_hit_multiplier 1.5
  @headshot_multiplier 2.0
  @distance_damage_falloff 0.8

  @type damage_result :: %{
    base_damage: float(),
    modified_damage: float(),
    is_critical: boolean(),
    is_headshot: boolean(),
    damage_type: atom()
  }

  @spec calculate_damage(Weapon.t(), Player.t(), Player.t(), map()) :: damage_result()
  def calculate_damage(weapon, attacker, target, hit_info) do
    base_damage = get_base_damage(weapon, hit_info.distance)
    
    damage_modifiers = %{
      critical: calculate_critical_hit(attacker),
      headshot: calculate_headshot(hit_info),
      power_ups: calculate_power_up_modifiers(attacker, target),
      weapon_proficiency: calculate_proficiency_bonus(attacker, weapon)
    }
    
    modified_damage = apply_damage_modifiers(base_damage, damage_modifiers)
    
    %{
      base_damage: base_damage,
      modified_damage: modified_damage,
      is_critical: damage_modifiers.critical.active,
      is_headshot: damage_modifiers.headshot.active,
      damage_type: weapon.damage_type
    }
  end

  @spec get_base_damage(Weapon.t(), float()) :: float()
  defp get_base_damage(weapon, distance) do
    damage = weapon.base_damage
    
    if distance > weapon.effective_range do
      damage * calculate_falloff(distance, weapon.effective_range)
    else
      damage
    end
  end

  @spec calculate_falloff(float(), float()) :: float()
  defp calculate_falloff(distance, effective_range) do
    falloff_distance = distance - effective_range
    falloff_factor = falloff_distance / effective_range
    max(@distance_damage_falloff, 1.0 - (falloff_factor * 0.3))
  end

  @spec calculate_critical_hit(Player.t()) :: map()
  defp calculate_critical_hit(attacker) do
    base_crit_chance = @critical_hit_chance + (attacker.stats.accuracy * 0.1)
    is_critical = :rand.uniform() < base_crit_chance
    
    %{
      active: is_critical,
      multiplier: if(is_critical, do: @critical_hit_multiplier, else: 1.0)
    }
  end

  @spec calculate_headshot(map()) :: map()
  defp calculate_headshot(hit_info) do
    is_headshot = hit_info.hit_location == :head
    
    %{
      active: is_headshot,
      multiplier: if(is_headshot, do: @headshot_multiplier, else: 1.0)
    }
  end

  @spec calculate_power_up_modifiers(Player.t(), Player.t()) :: map()
  defp calculate_power_up_modifiers(attacker, target) do
    damage_boost = get_damage_boost(attacker.active_power_ups)
    damage_reduction = get_damage_reduction(target.active_power_ups)
    
    %{
      damage_boost: damage_boost,
      damage_reduction: damage_reduction
    }
  end

  @spec get_damage_boost([PowerUp.t()]) :: float()
  defp get_damage_boost(power_ups) do
    power_ups
    |> Enum.filter(&(&1.type == :damage_boost))
    |> Enum.map(&(&1.modifier))
    |> Enum.sum()
    |> Kernel.+(1.0)
  end

  @spec get_damage_reduction([PowerUp.t()]) :: float()
  defp get_damage_reduction(power_ups) do
    power_ups
    |> Enum.filter(&(&1.type == :damage_reduction))
    |> Enum.map(&(&1.modifier))
    |> Enum.sum()
    |> min(0.8) # Cap damage reduction at 80%
  end

  @spec calculate_proficiency_bonus(Player.t(), Weapon.t()) :: float()
  defp calculate_proficiency_bonus(player, weapon) do
    proficiency = Map.get(player.weapon_proficiency, weapon.type, 0)
    1.0 + (proficiency * 0.05) # 5% bonus per proficiency level
  end

  @spec apply_damage_modifiers(float(), map()) :: float()
  defp apply_damage_modifiers(base_damage, modifiers) do
    base_damage
    |> apply_multiplier(modifiers.critical.multiplier)
    |> apply_multiplier(modifiers.headshot.multiplier)
    |> apply_multiplier(modifiers.power_ups.damage_boost)
    |> apply_multiplier(modifiers.weapon_proficiency)
    |> apply_damage_reduction(modifiers.power_ups.damage_reduction)
    |> Float.round(2)
  end

  @spec apply_multiplier(float(), float()) :: float()
  defp apply_multiplier(damage, multiplier), do: damage * multiplier

  @spec apply_damage_reduction(float(), float()) :: float()
  defp apply_damage_reduction(damage, reduction), do: damage * (1.0 - reduction)
end