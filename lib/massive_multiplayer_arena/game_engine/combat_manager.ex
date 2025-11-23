defmodule MassiveMultiplayerArena.GameEngine.CombatManager do
  @moduledoc """
  Manages combat actions, damage calculation, and combat state transitions.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Weapon, Projectile, GameState}

  @type combat_action :: :attack | :block | :dodge | :cast_ability
  @type damage_type :: :physical | :magical | :true

  @doc """
  Processes a combat action between players.
  """
  @spec process_combat_action(GameState.t(), Player.id(), combat_action(), map()) :: GameState.t()
  def process_combat_action(game_state, player_id, action, params) do
    case action do
      :attack -> handle_attack(game_state, player_id, params)
      :block -> handle_block(game_state, player_id, params)
      :dodge -> handle_dodge(game_state, player_id, params)
      :cast_ability -> handle_ability_cast(game_state, player_id, params)
    end
  end

  @doc """
  Calculates damage based on attacker, defender, and weapon stats.
  """
  @spec calculate_damage(Player.t(), Player.t(), Weapon.t(), damage_type()) :: non_neg_integer()
  def calculate_damage(attacker, defender, weapon, damage_type \\ :physical) do
    base_damage = weapon.damage + attacker.stats.attack
    defense = get_defense(defender, damage_type)
    
    # Apply damage reduction and critical hit chance
    damage_after_defense = max(1, base_damage - defense)
    
    if critical_hit?(attacker) do
      round(damage_after_defense * 1.5)
    else
      damage_after_defense
    end
  end

  @doc """
  Applies damage to a player and handles death state.
  """
  @spec apply_damage(Player.t(), non_neg_integer()) :: Player.t()
  def apply_damage(player, damage) do
    new_health = max(0, player.health - damage)
    
    %{player | 
      health: new_health,
      alive: new_health > 0,
      last_damage_time: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Checks if a player can perform a combat action based on cooldowns and state.
  """
  @spec can_perform_action?(Player.t(), combat_action()) :: boolean()
  def can_perform_action?(player, action) do
    current_time = System.monotonic_time(:millisecond)
    
    case action do
      :attack -> 
        player.alive and 
        current_time >= player.last_attack_time + player.weapon.attack_speed
      
      :block -> 
        player.alive and 
        current_time >= player.last_block_time + player.block_cooldown
      
      :dodge -> 
        player.alive and 
        current_time >= player.last_dodge_time + player.dodge_cooldown and
        player.stamina >= player.dodge_cost
      
      :cast_ability -> 
        player.alive and 
        player.mana >= get_ability_cost(player.selected_ability)
    end
  end

  # Private functions
  
  defp handle_attack(game_state, attacker_id, %{target_id: target_id, weapon: weapon}) do
    attacker = Map.get(game_state.players, attacker_id)
    target = Map.get(game_state.players, target_id)
    
    if can_perform_action?(attacker, :attack) and target.alive do
      damage = calculate_damage(attacker, target, weapon)
      updated_target = apply_damage(target, damage)
      updated_attacker = %{attacker | last_attack_time: System.monotonic_time(:millisecond)}
      
      updated_players = game_state.players
        |> Map.put(attacker_id, updated_attacker)
        |> Map.put(target_id, updated_target)
      
      %{game_state | players: updated_players}
    else
      game_state
    end
  end
  
  defp handle_block(game_state, player_id, _params) do
    player = Map.get(game_state.players, player_id)
    
    if can_perform_action?(player, :block) do
      updated_player = %{player | 
        blocking: true,
        last_block_time: System.monotonic_time(:millisecond),
        block_end_time: System.monotonic_time(:millisecond) + player.block_duration
      }
      
      updated_players = Map.put(game_state.players, player_id, updated_player)
      %{game_state | players: updated_players}
    else
      game_state
    end
  end
  
  defp handle_dodge(game_state, player_id, %{direction: direction}) do
    player = Map.get(game_state.players, player_id)
    
    if can_perform_action?(player, :dodge) do
      dodge_distance = 50
      {dx, dy} = direction_to_vector(direction)
      
      new_x = player.x + dx * dodge_distance
      new_y = player.y + dy * dodge_distance
      
      updated_player = %{player |
        x: new_x,
        y: new_y,
        stamina: player.stamina - player.dodge_cost,
        invulnerable: true,
        invulnerable_end_time: System.monotonic_time(:millisecond) + 200,
        last_dodge_time: System.monotonic_time(:millisecond)
      }
      
      updated_players = Map.put(game_state.players, player_id, updated_player)
      %{game_state | players: updated_players}
    else
      game_state
    end
  end
  
  defp handle_ability_cast(game_state, player_id, %{ability: ability, target_pos: {x, y}}) do
    player = Map.get(game_state.players, player_id)
    
    if can_perform_action?(player, :cast_ability) do
      mana_cost = get_ability_cost(ability)
      
      updated_player = %{player |
        mana: player.mana - mana_cost,
        casting: true,
        cast_end_time: System.monotonic_time(:millisecond) + get_cast_time(ability)
      }
      
      # Apply ability effect based on type
      game_state = apply_ability_effect(game_state, player_id, ability, {x, y})
      
      updated_players = Map.put(game_state.players, player_id, updated_player)
      %{game_state | players: updated_players}
    else
      game_state
    end
  end
  
  defp get_defense(player, :physical), do: player.stats.armor
  defp get_defense(player, :magical), do: player.stats.magic_resist
  defp get_defense(_player, :true), do: 0
  
  defp critical_hit?(player) do
    :rand.uniform(100) <= player.stats.critical_chance
  end
  
  defp direction_to_vector(:north), do: {0, -1}
  defp direction_to_vector(:south), do: {0, 1}
  defp direction_to_vector(:east), do: {1, 0}
  defp direction_to_vector(:west), do: {-1, 0}
  defp direction_to_vector(:northeast), do: {0.707, -0.707}
  defp direction_to_vector(:northwest), do: {-0.707, -0.707}
  defp direction_to_vector(:southeast), do: {0.707, 0.707}
  defp direction_to_vector(:southwest), do: {-0.707, 0.707}
  
  defp get_ability_cost(:fireball), do: 25
  defp get_ability_cost(:heal), do: 30
  defp get_ability_cost(:lightning), do: 40
  defp get_ability_cost(_), do: 20
  
  defp get_cast_time(:fireball), do: 1000
  defp get_cast_time(:heal), do: 2000
  defp get_cast_time(:lightning), do: 800
  defp get_cast_time(_), do: 1500
  
  defp apply_ability_effect(game_state, _player_id, :fireball, {x, y}) do
    # Create explosion projectile
    projectile = %Projectile{
      id: generate_id(),
      x: x,
      y: y,
      type: :explosion,
      damage: 75,
      radius: 100,
      duration: 500
    }
    
    %{game_state | projectiles: [projectile | game_state.projectiles]}
  end
  
  defp apply_ability_effect(game_state, player_id, :heal, _pos) do
    player = Map.get(game_state.players, player_id)
    healed_player = %{player | health: min(player.max_health, player.health + 50)}
    
    updated_players = Map.put(game_state.players, player_id, healed_player)
    %{game_state | players: updated_players}
  end
  
  defp apply_ability_effect(game_state, player_id, :lightning, {x, y}) do
    # Find closest enemy to lightning target
    attacker = Map.get(game_state.players, player_id)
    
    closest_enemy = game_state.players
    |> Enum.filter(fn {id, player} -> 
        id != player_id and player.alive and 
        distance({player.x, player.y}, {x, y}) <= 150
      end)
    |> Enum.min_by(fn {_id, player} -> distance({player.x, player.y}, {x, y}) end, fn -> nil end)
    
    case closest_enemy do
      {enemy_id, enemy} ->
        damaged_enemy = apply_damage(enemy, 60)
        updated_players = Map.put(game_state.players, enemy_id, damaged_enemy)
        %{game_state | players: updated_players}
      
      nil -> game_state
    end
  end
  
  defp apply_ability_effect(game_state, _player_id, _ability, _pos), do: game_state
  
  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))
  end
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end