defmodule MassiveMultiplayerArena.GameEngine.SpatialGrid do
  @moduledoc """
  Optimized spatial grid implementation for efficient collision detection.
  Uses dynamic cell sizing and lazy bucket creation for better memory usage.
  """

  defstruct grid: %{}, cell_size: 64, bounds: {0, 0, 1024, 1024}, stats: %{queries: 0, hits: 0}

  @type t :: %__MODULE__{
    grid: map(),
    cell_size: integer(),
    bounds: {number(), number(), number(), number()},
    stats: map()
  }

  @type entity :: %{
    id: term(),
    x: number(),
    y: number(),
    width: number(),
    height: number()
  }

  def new(cell_size \\ 64, bounds \\ {0, 0, 1024, 1024}) do
    %__MODULE__{
      cell_size: cell_size,
      bounds: bounds,
      stats: %{queries: 0, hits: 0, buckets: 0}
    }
  end

  def insert(%__MODULE__{} = grid, entity) do
    cells = get_entity_cells(grid, entity)
    new_grid = Enum.reduce(cells, grid.grid, fn cell_key, acc ->
      Map.update(acc, cell_key, [entity], &[entity | &1])
    end)
    
    %{grid | grid: new_grid, stats: update_stats(grid.stats, :buckets, map_size(new_grid))}
  end

  def remove(%__MODULE__{} = grid, entity_id) do
    new_grid = Enum.reduce(grid.grid, %{}, fn {cell_key, entities}, acc ->
      filtered = Enum.reject(entities, &(&1.id == entity_id))
      if Enum.empty?(filtered) do
        acc
      else
        Map.put(acc, cell_key, filtered)
      end
    end)
    
    %{grid | grid: new_grid, stats: update_stats(grid.stats, :buckets, map_size(new_grid))}
  end

  def query_region(%__MODULE__{} = grid, x, y, width, height) do
    region = %{x: x, y: y, width: width, height: height}
    cells = get_region_cells(grid, region)
    
    entities = cells
    |> Enum.flat_map(&Map.get(grid.grid, &1, []))
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(&entities_overlap?(region, &1))
    
    new_stats = grid.stats
    |> update_stats(:queries, grid.stats.queries + 1)
    |> update_stats(:hits, grid.stats.hits + length(entities))
    
    {entities, %{grid | stats: new_stats}}
  end

  def get_nearby_entities(%__MODULE__{} = grid, entity, radius \\ 100) do
    x = entity.x - radius
    y = entity.y - radius
    width = entity.width + (2 * radius)
    height = entity.height + (2 * radius)
    
    {entities, updated_grid} = query_region(grid, x, y, width, height)
    nearby = Enum.reject(entities, &(&1.id == entity.id))
    
    {nearby, updated_grid}
  end

  def clear(%__MODULE__{} = grid) do
    %{grid | grid: %{}, stats: %{queries: 0, hits: 0, buckets: 0}}
  end

  def get_stats(%__MODULE__{stats: stats}), do: stats

  # Private functions
  
  defp get_entity_cells(%__MODULE__{cell_size: cell_size}, entity) do
    left = div(trunc(entity.x), cell_size)
    right = div(trunc(entity.x + entity.width), cell_size)
    top = div(trunc(entity.y), cell_size)
    bottom = div(trunc(entity.y + entity.height), cell_size)
    
    for x <- left..right, y <- top..bottom do
      {x, y}
    end
  end

  defp get_region_cells(%__MODULE__{cell_size: cell_size}, region) do
    left = div(trunc(region.x), cell_size)
    right = div(trunc(region.x + region.width), cell_size)
    top = div(trunc(region.y), cell_size)
    bottom = div(trunc(region.y + region.height), cell_size)
    
    for x <- left..right, y <- top..bottom do
      {x, y}
    end
  end

  defp entities_overlap?(region1, region2) do
    not (
      region1.x + region1.width < region2.x or
      region2.x + region2.width < region1.x or
      region1.y + region1.height < region2.y or
      region2.y + region2.height < region1.y
    )
  end

  defp update_stats(stats, key, value) do
    Map.put(stats, key, value)
  end
end