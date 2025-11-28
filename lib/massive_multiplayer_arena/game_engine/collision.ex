defmodule MassiveMultiplayerArena.GameEngine.Collision do
  @moduledoc """
  Handles collision detection between game entities using spatial partitioning.
  """

  alias MassiveMultiplayerArena.GameEngine.{
    Player,
    Projectile,
    PowerUp,
    SpatialGrid
  }

  @type collision_result :: {
    :collision,
    {entity_type(), binary()},
    {entity_type(), binary()}
  }

  @type entity_type :: :player | :projectile | :power_up

  @spec check_collisions(SpatialGrid.t(), map(), map(), map()) :: [collision_result()]
  def check_collisions(spatial_grid, players, projectiles, power_ups) do
    all_entities = %{}
                  |> Map.merge(for {id, player} <- players, into: %{}, do: {id, {:player, player}})
                  |> Map.merge(for {id, projectile} <- projectiles, into: %{}, do: {id, {:projectile, projectile}})
                  |> Map.merge(for {id, power_up} <- power_ups, into: %{}, do: {id, {:power_up, power_up}})

    all_entities
    |> Enum.flat_map(fn {entity_id, {entity_type, entity}} ->
      {x, y} = get_entity_position(entity)
      radius = get_entity_radius(entity_type)
      
      nearby_ids = SpatialGrid.get_nearby_objects(spatial_grid, x, y, radius)
      
      nearby_ids
      |> Enum.reject(&(&1 == entity_id))
      |> Enum.filter_map(
        fn other_id -> Map.has_key?(all_entities, other_id) end,
        fn other_id ->
          {other_type, other_entity} = all_entities[other_id]
          
          if should_check_collision(entity_type, other_type) and
             entities_colliding?(entity, other_entity, entity_type, other_type) do
            {:collision, {entity_type, entity_id}, {other_type, other_id}}
          else
            nil
          end
        end
      )
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.uniq_by(fn {:collision, {_, id1}, {_, id2}} ->
      Enum.sort([id1, id2])
    end)
  end

  @spec check_player_collisions(Player.t(), [Player.t()]) :: [Player.t()]
  def check_player_collisions(%Player{} = player, other_players) do
    Enum.filter(other_players, fn other_player ->
      player.id != other_player.id and players_colliding?(player, other_player)
    end)
  end

  @spec check_projectile_collisions(Projectile.t(), [Player.t()]) :: [Player.t()]
  def check_projectile_collisions(%Projectile{} = projectile, players) do
    Enum.filter(players, fn player ->
      projectile.owner_id != player.id and
      projectile_player_collision?(projectile, player)
    end)
  end

  @spec check_power_up_collisions(PowerUp.t(), [Player.t()]) :: [Player.t()]
  def check_power_up_collisions(%PowerUp{} = power_up, players) do
    Enum.filter(players, &power_up_player_collision?(power_up, &1))
  end

  @spec players_colliding?(Player.t(), Player.t()) :: boolean()
  def players_colliding?(%Player{} = p1, %Player{} = p2) do
    distance_squared = 
      :math.pow(p1.x - p2.x, 2) + :math.pow(p1.y - p2.y, 2)
    
    collision_distance_squared = :math.pow(p1.radius + p2.radius, 2)
    
    distance_squared <= collision_distance_squared
  end

  @spec projectile_player_collision?(Projectile.t(), Player.t()) :: boolean()
  def projectile_player_collision?(%Projectile{} = proj, %Player{} = player) do
    distance_squared = 
      :math.pow(proj.x - player.x, 2) + :math.pow(proj.y - player.y, 2)
    
    collision_distance_squared = :math.pow(proj.radius + player.radius, 2)
    
    distance_squared <= collision_distance_squared
  end

  @spec power_up_player_collision?(PowerUp.t(), Player.t()) :: boolean()
  def power_up_player_collision?(%PowerUp{} = power_up, %Player{} = player) do
    distance_squared = 
      :math.pow(power_up.x - player.x, 2) + :math.pow(power_up.y - player.y, 2)
    
    collision_distance_squared = :math.pow(power_up.radius + player.radius, 2)
    
    distance_squared <= collision_distance_squared
  end

  # Private functions

  defp get_entity_position(%Player{x: x, y: y}), do: {x, y}
  defp get_entity_position(%Projectile{x: x, y: y}), do: {x, y}
  defp get_entity_position(%PowerUp{x: x, y: y}), do: {x, y}

  defp get_entity_radius(:player), do: 15.0
  defp get_entity_radius(:projectile), do: 3.0
  defp get_entity_radius(:power_up), do: 10.0

  defp should_check_collision(:player, :player), do: true
  defp should_check_collision(:projectile, :player), do: true
  defp should_check_collision(:player, :projectile), do: true
  defp should_check_collision(:power_up, :player), do: true
  defp should_check_collision(:player, :power_up), do: true
  defp should_check_collision(_, _), do: false

  defp entities_colliding?(entity1, entity2, type1, type2) do
    {x1, y1} = get_entity_position(entity1)
    {x2, y2} = get_entity_position(entity2)
    
    r1 = get_entity_radius(type1)
    r2 = get_entity_radius(type2)
    
    distance_squared = :math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2)
    collision_distance_squared = :math.pow(r1 + r2, 2)
    
    distance_squared <= collision_distance_squared
  end
end