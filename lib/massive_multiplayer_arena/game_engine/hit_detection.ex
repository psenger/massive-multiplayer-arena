defmodule MassiveMultiplayerArena.GameEngine.HitDetection do
  @moduledoc """
  Handles hit detection for projectiles and hitscan weapons,
  including hit location determination and line-of-sight checks.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Projectile, WorldBounds}

  @hit_locations [:head, :torso, :arms, :legs]
  @head_hitbox_size 0.3
  @torso_hitbox_size 0.6
  @limb_hitbox_size 0.4

  @type hit_result :: %{
    hit: boolean(),
    target: Player.t() | nil,
    hit_location: atom() | nil,
    hit_point: {float(), float()} | nil,
    distance: float()
  }

  @spec check_projectile_hit(Projectile.t(), [Player.t()]) :: hit_result()
  def check_projectile_hit(projectile, players) do
    target_players = Enum.filter(players, &(&1.id != projectile.owner_id and &1.alive?))
    
    case find_closest_hit(projectile, target_players) do
      nil -> %{hit: false, target: nil, hit_location: nil, hit_point: nil, distance: 0}
      hit -> hit
    end
  end

  @spec check_hitscan_hit({float(), float()}, {float(), float()}, [Player.t()], String.t()) :: hit_result()
  def check_hitscan_hit(start_pos, end_pos, players, shooter_id) do
    target_players = Enum.filter(players, &(&1.id != shooter_id and &1.alive?))
    
    case find_hitscan_target(start_pos, end_pos, target_players) do
      nil -> 
        distance = calculate_distance(start_pos, end_pos)
        %{hit: false, target: nil, hit_location: nil, hit_point: nil, distance: distance}
      hit -> hit
    end
  end

  @spec find_closest_hit(Projectile.t(), [Player.t()]) :: hit_result() | nil
  defp find_closest_hit(projectile, players) do
    projectile_pos = {projectile.x, projectile.y}
    
    players
    |> Enum.map(&check_player_collision(projectile_pos, &1))
    |> Enum.filter(& &1.hit)
    |> Enum.min_by(& &1.distance, fn -> nil end)
  end

  @spec find_hitscan_target({float(), float()}, {float(), float()}, [Player.t()]) :: hit_result() | nil
  defp find_hitscan_target(start_pos, end_pos, players) do
    players
    |> Enum.map(&check_line_intersection(start_pos, end_pos, &1))
    |> Enum.filter(& &1.hit)
    |> Enum.min_by(& &1.distance, fn -> nil end)
  end

  @spec check_player_collision({float(), float()}, Player.t()) :: hit_result()
  defp check_player_collision({proj_x, proj_y}, player) do
    player_pos = {player.x, player.y}
    distance = calculate_distance({proj_x, proj_y}, player_pos)
    
    if distance <= player.collision_radius do
      hit_location = determine_hit_location({proj_x, proj_y}, player)
      %{
        hit: true,
        target: player,
        hit_location: hit_location,
        hit_point: {proj_x, proj_y},
        distance: distance
      }
    else
      %{hit: false, target: nil, hit_location: nil, hit_point: nil, distance: distance}
    end
  end

  @spec check_line_intersection({float(), float()}, {float(), float()}, Player.t()) :: hit_result()
  defp check_line_intersection(start_pos, end_pos, player) do
    player_pos = {player.x, player.y}
    
    case line_circle_intersection(start_pos, end_pos, player_pos, player.collision_radius) do
      nil -> 
        distance = calculate_distance(start_pos, player_pos)
        %{hit: false, target: nil, hit_location: nil, hit_point: nil, distance: distance}
      
      intersection_point ->
        distance = calculate_distance(start_pos, intersection_point)
        hit_location = determine_hit_location(intersection_point, player)
        %{
          hit: true,
          target: player,
          hit_location: hit_location,
          hit_point: intersection_point,
          distance: distance
        }
    end
  end

  @spec line_circle_intersection({float(), float()}, {float(), float()}, {float(), float()}, float()) :: {float(), float()} | nil
  defp line_circle_intersection({x1, y1}, {x2, y2}, {cx, cy}, radius) do
    # Vector from line start to circle center
    dx = cx - x1
    dy = cy - y1
    
    # Line direction vector
    ldx = x2 - x1
    ldy = y2 - y1
    
    # Project circle center onto line
    line_length_squared = ldx * ldx + ldy * ldy
    
    if line_length_squared == 0 do
      # Line is a point, check if it's within circle
      if dx * dx + dy * dy <= radius * radius do
        {x1, y1}
      else
        nil
      end
    else
      t = max(0, min(1, (dx * ldx + dy * ldy) / line_length_squared))
      
      # Closest point on line segment
      closest_x = x1 + t * ldx
      closest_y = y1 + t * ldy
      
      # Check if closest point is within circle
      dist_squared = (closest_x - cx) * (closest_x - cx) + (closest_y - cy) * (closest_y - cy)
      
      if dist_squared <= radius * radius do
        {closest_x, closest_y}
      else
        nil
      end
    end
  end

  @spec determine_hit_location({float(), float()}, Player.t()) :: atom()
  defp determine_hit_location({hit_x, hit_y}, player) do
    # Calculate relative position from player center
    rel_x = hit_x - player.x
    rel_y = hit_y - player.y
    
    # Determine hit location based on relative position
    cond do
      abs(rel_y) < @head_hitbox_size and rel_y > 0 -> :head
      abs(rel_y) < @torso_hitbox_size and rel_y <= 0 -> :torso
      abs(rel_x) > @limb_hitbox_size -> :arms
      true -> :legs
    end
  end

  @spec calculate_distance({float(), float()}, {float(), float()}) :: float()
  defp calculate_distance({x1, y1}, {x2, y2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end
end