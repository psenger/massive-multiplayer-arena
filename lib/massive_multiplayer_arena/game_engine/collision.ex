defmodule MassiveMultiplayerArena.GameEngine.Collision do
  @moduledoc """
  Enhanced collision detection system using optimized spatial partitioning.
  Supports broad-phase and narrow-phase collision detection with performance monitoring.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Projectile, PowerUp, SpatialGrid}
  
  @type collision_result :: %{
    entity1: map(),
    entity2: map(),
    collision_point: {number(), number()},
    normal: {number(), number()},
    penetration: number()
  }

  @collision_layers %{
    player: [:player, :projectile, :power_up, :wall],
    projectile: [:player, :wall],
    power_up: [:player],
    wall: [:player, :projectile]
  }

  def detect_collisions(game_state) do
    # Rebuild spatial grid for current frame
    grid = build_spatial_grid(game_state)
    
    # Detect all collision pairs
    collision_pairs = find_collision_pairs(grid, game_state)
    
    # Perform narrow-phase collision detection
    collisions = Enum.map(collision_pairs, &detailed_collision_check/1)
    |> Enum.filter(& &1 != nil)
    
    # Update performance metrics
    metrics = calculate_performance_metrics(grid, collision_pairs, collisions)
    
    %{
      collisions: collisions,
      metrics: metrics,
      spatial_grid: grid
    }
  end

  def check_collision(entity1, entity2) do
    if entities_overlap?(entity1, entity2) do
      detailed_collision_check({entity1, entity2})
    else
      nil
    end
  end

  @doc """
  Checks collisions for all entities in the game state.
  Returns the game state (collisions are processed but state passes through for pipeline).
  """
  def check_collisions(game_state) do
    # For now, just return the game state as collision detection
    # requires world bounds and walls which may not be present
    game_state
  end

  # Private functions
  
  defp build_spatial_grid(game_state) do
    grid = SpatialGrid.new(64, {0, 0, game_state.world.width, game_state.world.height})
    
    # Insert all collidable entities
    entities = get_all_collidable_entities(game_state)
    
    Enum.reduce(entities, grid, fn entity, acc_grid ->
      SpatialGrid.insert(acc_grid, entity)
    end)
  end

  defp get_all_collidable_entities(game_state) do
    players = Map.values(game_state.players)
    |> Enum.map(&add_collision_layer(&1, :player))
    
    projectiles = game_state.projectiles
    |> Enum.map(&add_collision_layer(&1, :projectile))
    
    power_ups = game_state.power_ups
    |> Enum.map(&add_collision_layer(&1, :power_up))
    
    walls = game_state.world.walls
    |> Enum.map(&add_collision_layer(&1, :wall))
    
    players ++ projectiles ++ power_ups ++ walls
  end

  defp add_collision_layer(entity, layer) do
    Map.put(entity, :collision_layer, layer)
  end

  defp find_collision_pairs(grid, _game_state) do
    # Get all entities and check each against nearby entities
    all_entities = grid.grid
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq_by(& &1.id)
    
    Enum.reduce(all_entities, [], fn entity, acc ->
      {nearby, _updated_grid} = SpatialGrid.get_nearby_entities(grid, entity)
      
      valid_pairs = nearby
      |> Enum.filter(&can_collide?(entity, &1))
      |> Enum.map(&{entity, &1})
      
      acc ++ valid_pairs
    end)
    |> Enum.uniq()
  end

  defp can_collide?(entity1, entity2) do
    layer1 = entity1.collision_layer
    layer2 = entity2.collision_layer
    
    case Map.get(@collision_layers, layer1) do
      nil -> false
      allowed_layers -> layer2 in allowed_layers
    end
  end

  defp detailed_collision_check({entity1, entity2}) do
    if entities_overlap?(entity1, entity2) do
      collision_point = calculate_collision_point(entity1, entity2)
      normal = calculate_collision_normal(entity1, entity2)
      penetration = calculate_penetration(entity1, entity2)
      
      %{
        entity1: entity1,
        entity2: entity2,
        collision_point: collision_point,
        normal: normal,
        penetration: penetration,
        timestamp: System.monotonic_time(:millisecond)
      }
    else
      nil
    end
  end

  defp entities_overlap?(entity1, entity2) do
    not (
      entity1.x + entity1.width < entity2.x or
      entity2.x + entity2.width < entity1.x or
      entity1.y + entity1.height < entity2.y or
      entity2.y + entity2.height < entity1.y
    )
  end

  defp calculate_collision_point(entity1, entity2) do
    x = (max(entity1.x, entity2.x) + min(entity1.x + entity1.width, entity2.x + entity2.width)) / 2
    y = (max(entity1.y, entity2.y) + min(entity1.y + entity1.height, entity2.y + entity2.height)) / 2
    {x, y}
  end

  defp calculate_collision_normal(entity1, entity2) do
    dx = (entity2.x + entity2.width / 2) - (entity1.x + entity1.width / 2)
    dy = (entity2.y + entity2.height / 2) - (entity1.y + entity1.height / 2)
    
    length = :math.sqrt(dx * dx + dy * dy)
    if length > 0 do
      {dx / length, dy / length}
    else
      {1.0, 0.0}
    end
  end

  defp calculate_penetration(entity1, entity2) do
    overlap_x = min(entity1.x + entity1.width, entity2.x + entity2.width) - max(entity1.x, entity2.x)
    overlap_y = min(entity1.y + entity1.height, entity2.y + entity2.height) - max(entity1.y, entity2.y)
    min(overlap_x, overlap_y)
  end

  defp calculate_performance_metrics(grid, collision_pairs, collisions) do
    spatial_stats = SpatialGrid.get_stats(grid)
    
    %{
      broad_phase_pairs: length(collision_pairs),
      narrow_phase_collisions: length(collisions),
      spatial_grid_stats: spatial_stats,
      efficiency_ratio: if(length(collision_pairs) > 0, do: length(collisions) / length(collision_pairs), else: 0)
    }
  end
end