defmodule MassiveMultiplayerArena.GameEngine.SpatialGrid do
  @moduledoc """
  Spatial partitioning grid for efficient collision detection.
  Divides game world into cells to reduce collision check complexity.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Projectile}

  @grid_size 50
  @world_width 1000
  @world_height 1000
  @cells_x div(@world_width, @grid_size)
  @cells_y div(@world_height, @grid_size)

  defstruct grid: %{}, objects: %{}

  @type t :: %__MODULE__{
    grid: %{binary() => [binary()]},
    objects: %{binary() => {float(), float(), float()}}
  }

  @spec new() :: t()
  def new do
    %__MODULE_{
      grid: initialize_grid(),
      objects: %{}
    }
  end

  @spec add_object(t(), binary(), float(), float(), float()) :: t()
  def add_object(%__MODULE__{} = spatial_grid, object_id, x, y, radius) do
    cells = get_cells_for_object(x, y, radius)
    
    updated_grid = 
      Enum.reduce(cells, spatial_grid.grid, fn cell_key, grid ->
        Map.update(grid, cell_key, [object_id], &[object_id | &1])
      end)
    
    updated_objects = Map.put(spatial_grid.objects, object_id, {x, y, radius})
    
    %{spatial_grid | grid: updated_grid, objects: updated_objects}
  end

  @spec remove_object(t(), binary()) :: t()
  def remove_object(%__MODULE__{} = spatial_grid, object_id) do
    case Map.get(spatial_grid.objects, object_id) do
      nil -> spatial_grid
      {x, y, radius} ->
        cells = get_cells_for_object(x, y, radius)
        
        updated_grid = 
          Enum.reduce(cells, spatial_grid.grid, fn cell_key, grid ->
            Map.update(grid, cell_key, [], &List.delete(&1, object_id))
          end)
        
        updated_objects = Map.delete(spatial_grid.objects, object_id)
        
        %{spatial_grid | grid: updated_grid, objects: updated_objects}
    end
  end

  @spec update_object(t(), binary(), float(), float(), float()) :: t()
  def update_object(%__MODULE__{} = spatial_grid, object_id, x, y, radius) do
    spatial_grid
    |> remove_object(object_id)
    |> add_object(object_id, x, y, radius)
  end

  @spec get_nearby_objects(t(), float(), float(), float()) :: [binary()]
  def get_nearby_objects(%__MODULE__{} = spatial_grid, x, y, radius) do
    cells = get_cells_for_object(x, y, radius)
    
    cells
    |> Enum.flat_map(fn cell_key ->
      Map.get(spatial_grid.grid, cell_key, [])
    end)
    |> Enum.uniq()
  end

  @spec clear(t()) :: t()
  def clear(%__MODULE__{}) do
    new()
  end

  # Private functions

  defp initialize_grid do
    for x <- 0..(@cells_x - 1),
        y <- 0..(@cells_y - 1),
        into: %{} do
      {cell_key(x, y), []}
    end
  end

  defp get_cells_for_object(x, y, radius) do
    min_x = max(0, div(trunc(x - radius), @grid_size))
    max_x = min(@cells_x - 1, div(trunc(x + radius), @grid_size))
    min_y = max(0, div(trunc(y - radius), @grid_size))
    max_y = min(@cells_y - 1, div(trunc(y + radius), @grid_size))
    
    for cell_x <- min_x..max_x,
        cell_y <- min_y..max_y do
      cell_key(cell_x, cell_y)
    end
  end

  defp cell_key(x, y), do: "#{x},#{y}"
end