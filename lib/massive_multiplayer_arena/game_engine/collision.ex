defmodule MassiveMultiplayerArena.GameEngine.Collision do
  @moduledoc """
  Collision detection system for game entities.
  """

  alias MassiveMultiplayerArena.GameEngine.Player

  @doc """
  Checks if two players are colliding using circular collision detection.
  """
  def check_collision(%Player{} = player1, %Player{} = player2) do
    case safe_distance_calculation(player1.position, player2.position) do
      {:ok, distance} ->
        collision_distance = player1.radius + player2.radius
        distance <= collision_distance
      
      {:error, _reason} ->
        false
    end
  end

  @doc """
  Calculates collision normal between two players.
  """
  def collision_normal(%Player{} = player1, %Player{} = player2) do
    case safe_vector_calculation(player1.position, player2.position) do
      {:ok, normal} -> normal
      {:error, _reason} -> %{x: 1.0, y: 0.0}  # Default normal
    end
  end

  @doc """
  Separates two overlapping players to prevent intersection.
  """
  def separate_players(%Player{} = player1, %Player{} = player2) do
    case safe_distance_calculation(player1.position, player2.position) do
      {:ok, distance} when distance > 0 ->
        overlap = (player1.radius + player2.radius) - distance
        
        if overlap > 0 do
          # Calculate separation vector
          dx = player2.position.x - player1.position.x
          dy = player2.position.y - player1.position.y
          
          # Normalize and apply separation
          separation_factor = overlap / (2 * distance)
          separation_x = dx * separation_factor
          separation_y = dy * separation_factor
          
          # Update positions
          updated_player1 = %{player1 | 
            position: %{
              x: player1.position.x - separation_x,
              y: player1.position.y - separation_y
            }
          }
          
          updated_player2 = %{player2 |
            position: %{
              x: player2.position.x + separation_x,
              y: player2.position.y + separation_y
            }
          }
          
          {updated_player1, updated_player2}
        else
          {player1, player2}
        end
      
      _ ->
        # If distance calculation fails, apply minimal separation
        minimal_separation = 1.0
        updated_player1 = %{player1 |
          position: %{
            x: player1.position.x - minimal_separation,
            y: player1.position.y
          }
        }
        
        updated_player2 = %{player2 |
          position: %{
            x: player2.position.x + minimal_separation,
            y: player2.position.y
          }
        }
        
        {updated_player1, updated_player2}
    end
  end

  defp safe_distance_calculation(pos1, pos2) do
    try do
      dx = pos2.x - pos1.x
      dy = pos2.y - pos1.y
      distance = :math.sqrt(dx * dx + dy * dy)
      
      if is_number(distance) and distance >= 0 do
        {:ok, distance}
      else
        {:error, :invalid_distance}
      end
    rescue
      ArithmeticError -> {:error, :arithmetic_error}
      _ -> {:error, :unknown_error}
    end
  end

  defp safe_vector_calculation(pos1, pos2) do
    case safe_distance_calculation(pos1, pos2) do
      {:ok, distance} when distance > 0 ->
        dx = pos2.x - pos1.x
        dy = pos2.y - pos1.y
        {:ok, %{x: dx / distance, y: dy / distance}}
      
      _ ->
        {:error, :invalid_vector}
    end
  end
end