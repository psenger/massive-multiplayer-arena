defmodule MassiveMultiplayerArena.GameEngine.PowerUp do
  @moduledoc """
  Power-up system for temporary player enhancements in the game.
  """

  defstruct [
    :id,
    :type,
    :x,
    :y,
    :active,
    :spawn_time,
    :duration,
    :effect_value,
    :respawn_delay
  ]

  @power_up_types %{
    speed_boost: %{duration: 10_000, effect_value: 1.5, respawn_delay: 30_000},
    damage_boost: %{duration: 15_000, effect_value: 2.0, respawn_delay: 45_000},
    health_pack: %{duration: 0, effect_value: 50, respawn_delay: 20_000},
    shield: %{duration: 12_000, effect_value: 0.5, respawn_delay: 60_000},
    rapid_fire: %{duration: 8_000, effect_value: 0.3, respawn_delay: 35_000}
  }

  @power_up_radius 20

  def new(id, type, x, y) when is_atom(type) and type in [:speed_boost, :damage_boost, :health_pack, :shield, :rapid_fire] do
    config = Map.get(@power_up_types, type)
    
    %__MODULE__{
      id: id,
      type: type,
      x: x,
      y: y,
      active: true,
      spawn_time: System.monotonic_time(:millisecond),
      duration: config.duration,
      effect_value: config.effect_value,
      respawn_delay: config.respawn_delay
    }
  end

  def can_collect?(power_up, player_x, player_y) do
    if power_up.active do
      distance = :math.sqrt(:math.pow(power_up.x - player_x, 2) + :math.pow(power_up.y - player_y, 2))
      distance <= @power_up_radius
    else
      false
    end
  end

  def collect(power_up) do
    %{power_up | active: false}
  end

  def should_respawn?(power_up) do
    if not power_up.active do
      current_time = System.monotonic_time(:millisecond)
      (current_time - power_up.spawn_time) >= power_up.respawn_delay
    else
      false
    end
  end

  def respawn(power_up) do
    %{power_up | active: true, spawn_time: System.monotonic_time(:millisecond)}
  end

  def apply_effect(player, power_up) do
    case power_up.type do
      :speed_boost ->
        effect_end_time = System.monotonic_time(:millisecond) + power_up.duration
        put_in(player.effects[:speed_boost], %{multiplier: power_up.effect_value, end_time: effect_end_time})
      
      :damage_boost ->
        effect_end_time = System.monotonic_time(:millisecond) + power_up.duration
        put_in(player.effects[:damage_boost], %{multiplier: power_up.effect_value, end_time: effect_end_time})
      
      :health_pack ->
        new_health = min(player.max_health, player.health + power_up.effect_value)
        %{player | health: new_health}
      
      :shield ->
        effect_end_time = System.monotonic_time(:millisecond) + power_up.duration
        put_in(player.effects[:shield], %{reduction: power_up.effect_value, end_time: effect_end_time})
      
      :rapid_fire ->
        effect_end_time = System.monotonic_time(:millisecond) + power_up.duration
        put_in(player.effects[:rapid_fire], %{cooldown_multiplier: power_up.effect_value, end_time: effect_end_time})
      
      _ ->
        player
    end
  end

  def get_spawn_positions(map_width, map_height) do
    # Predefined spawn positions for power-ups
    [
      {map_width * 0.2, map_height * 0.2},
      {map_width * 0.8, map_height * 0.2},
      {map_width * 0.5, map_height * 0.5},
      {map_width * 0.2, map_height * 0.8},
      {map_width * 0.8, map_height * 0.8}
    ]
  end

  def get_power_up_types, do: Map.keys(@power_up_types)
end