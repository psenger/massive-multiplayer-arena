defmodule MassiveMultiplayerArena.GameEngine.Player do
  @moduledoc """
  Represents a player entity in the game with position, health, and combat stats.
  """

  @type id :: String.t()
  @type t :: %__MODULE__{
    id: id(),
    user_id: String.t(),
    x: float(),
    y: float(),
    velocity_x: float(),
    velocity_y: float(),
    health: integer(),
    max_health: integer(),
    mana: integer(),
    max_mana: integer(),
    stamina: integer(),
    max_stamina: integer(),
    alive: boolean(),
    weapon: MassiveMultiplayerArena.GameEngine.Weapon.t(),
    stats: map(),
    last_attack_time: integer(),
    last_block_time: integer(),
    last_dodge_time: integer(),
    blocking: boolean(),
    block_end_time: integer(),
    invulnerable: boolean(),
    invulnerable_end_time: integer(),
    casting: boolean(),
    cast_end_time: integer(),
    selected_ability: atom(),
    block_duration: integer(),
    block_cooldown: integer(),
    dodge_cooldown: integer(),
    dodge_cost: integer(),
    last_damage_time: integer()
  }

  defstruct [
    :id,
    :user_id,
    x: 0.0,
    y: 0.0,
    velocity_x: 0.0,
    velocity_y: 0.0,
    health: 100,
    max_health: 100,
    mana: 100,
    max_mana: 100,
    stamina: 100,
    max_stamina: 100,
    alive: true,
    weapon: nil,
    stats: %{attack: 10, armor: 5, magic_resist: 3, critical_chance: 5},
    last_attack_time: 0,
    last_block_time: 0,
    last_dodge_time: 0,
    blocking: false,
    block_end_time: 0,
    invulnerable: false,
    invulnerable_end_time: 0,
    casting: false,
    cast_end_time: 0,
    selected_ability: :fireball,
    block_duration: 1000,
    block_cooldown: 2000,
    dodge_cooldown: 3000,
    dodge_cost: 20,
    last_damage_time: 0
  ]

  @doc """
  Creates a new player with the given ID and user ID.
  """
  @spec new(id(), String.t()) :: t()
  def new(id, user_id) do
    %__MODULE__{
      id: id,
      user_id: user_id,
      weapon: MassiveMultiplayerArena.GameEngine.Weapon.default()
    }
  end

  @doc """
  Updates player position with bounds checking.
  """
  @spec update_position(t(), float(), float()) :: t()
  def update_position(player, new_x, new_y) do
    %{player | x: new_x, y: new_y}
  end

  @doc """
  Updates player velocity for movement.
  """
  @spec update_velocity(t(), float(), float()) :: t()
  def update_velocity(player, velocity_x, velocity_y) do
    %{player | velocity_x: velocity_x, velocity_y: velocity_y}
  end

  @doc """
  Updates player's temporary states based on current time.
  """
  @spec update_states(t()) :: t()
  def update_states(player) do
    current_time = System.monotonic_time(:millisecond)
    
    player
    |> update_blocking_state(current_time)
    |> update_invulnerability_state(current_time)
    |> update_casting_state(current_time)
    |> regenerate_resources(current_time)
  end

  # Private helper functions
  
  defp update_blocking_state(player, current_time) do
    if player.blocking and current_time >= player.block_end_time do
      %{player | blocking: false, block_end_time: 0}
    else
      player
    end
  end
  
  defp update_invulnerability_state(player, current_time) do
    if player.invulnerable and current_time >= player.invulnerable_end_time do
      %{player | invulnerable: false, invulnerable_end_time: 0}
    else
      player
    end
  end
  
  defp update_casting_state(player, current_time) do
    if player.casting and current_time >= player.cast_end_time do
      %{player | casting: false, cast_end_time: 0}
    else
      player
    end
  end
  
  defp regenerate_resources(player, current_time) do
    # Regenerate mana and stamina over time
    time_since_last_damage = current_time - player.last_damage_time
    
    # Only regenerate if not recently damaged (3 seconds)
    if time_since_last_damage > 3000 do
      %{player |
        mana: min(player.max_mana, player.mana + 2),
        stamina: min(player.max_stamina, player.stamina + 3)
      }
    else
      %{player |
        stamina: min(player.max_stamina, player.stamina + 1)
      }
    end
  end
end