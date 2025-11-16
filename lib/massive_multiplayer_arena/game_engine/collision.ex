defmodule MassiveMultiplayerArena.GameEngine.Collision do
  @moduledoc """
  Handles collision detection between players and projectiles in the game world.
  """

  alias MassiveMultiplayerArena.GameEngine.Player
  alias MassiveMultiplayerArena.GameEngine.WorldBounds

  @player_radius 25
  @projectile_radius 5

  @doc """
  Detects collision between two players.
  """
  def player_collision?(%Player{} = player1, %Player{} = player2) do
    return false if player1.id == player2.id
    return false if player1.health <= 0 or player2.health <= 0
    
    distance = calculate_distance(player1.position, player2.position)
    distance <= (@player_radius * 2)
  end

  @doc """
  Detects collision between a player and a projectile.
  """
  def projectile_collision?(%Player{} = player, projectile) when is_map(projectile) do
    return false if player.health <= 0
    return false if projectile.owner_id == player.id
    return false if not Map.has_key?(projectile, :position) or not Map.has_key?(projectile, :active)
    return false if not projectile.active
    
    distance = calculate_distance(player.position, projectile.position)
    distance <= (@player_radius + @projectile_radius)
  end

  @doc """
  Checks if a position is within the world boundaries.
  """
  def within_bounds?(position) when is_map(position) do
    return false if not Map.has_key?(position, :x) or not Map.has_key?(position, :y)
    return false if not is_number(position.x) or not is_number(position.y)
    
    WorldBounds.within_bounds?(position)
  end

  @doc """
  Resolves collision between two players by separating them.
  """
  def resolve_player_collision(%Player{} = player1, %Player{} = player2) do
    if player_collision?(player1, player2) do
      # Calculate separation vector
      dx = player2.position.x - player1.position.x
      dy = player2.position.y - player1.position.y
      distance = :math.sqrt(dx * dx + dy * dy)
      
      # Avoid division by zero
      if distance > 0 do
        overlap = (@player_radius * 2) - distance
        separation_x = (dx / distance) * (overlap / 2)
        separation_y = (dy / distance) * (overlap / 2)
        
        player1_pos = %{
          x: max(0, player1.position.x - separation_x),
          y: max(0, player1.position.y - separation_y)
        }
        
        player2_pos = %{
          x: max(0, player2.position.x + separation_x),
          y: max(0, player2.position.y + separation_y)
        }
        
        # Ensure positions are within bounds
        player1_pos = WorldBounds.clamp_position(player1_pos)
        player2_pos = WorldBounds.clamp_position(player2_pos)
        
        {
          %{player1 | position: player1_pos},
          %{player2 | position: player2_pos}
        }
      else
        {player1, player2}
      end
    else
      {player1, player2}
    end
  end

  @doc """
  Calculates the distance between two positions.
  """
  defp calculate_distance(pos1, pos2) do
    return 0 if not is_map(pos1) or not is_map(pos2)
    return 0 if not Map.has_key?(pos1, :x) or not Map.has_key?(pos1, :y)
    return 0 if not Map.has_key?(pos2, :x) or not Map.has_key?(pos2, :y)
    return 0 if not is_number(pos1.x) or not is_number(pos1.y)
    return 0 if not is_number(pos2.x) or not is_number(pos2.y)
    
    dx = pos1.x - pos2.x
    dy = pos1.y - pos2.y
    :math.sqrt(dx * dx + dy * dy)
  end
end