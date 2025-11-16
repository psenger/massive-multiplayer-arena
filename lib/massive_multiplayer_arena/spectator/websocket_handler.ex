defmodule MassiveMultiplayerArena.Spectator.WebsocketHandler do
  @moduledoc """
  WebSocket handler for spectators to receive live game updates.
  """

  require Logger
  alias MassiveMultiplayerArena.Spectator.SpectatorRoom

  def init(req, opts) do
    {:cowboy_websocket, req, opts}
  end

  def websocket_init(state) do
    Logger.info("Spectator websocket connection initialized")
    {:ok, %{game_id: nil, room_id: nil, authenticated: false}}
  end

  def websocket_handle({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => "join_game", "game_id" => game_id}} ->
        handle_join_game(game_id, state)
      
      {:ok, %{"type" => "leave_game"}} ->
        handle_leave_game(state)
      
      {:error, _} ->
        error_response = Jason.encode!(%{"type" => "error", "message" => "Invalid JSON"})
        {:reply, {:text, error_response}, state}
      
      _ ->
        error_response = Jason.encode!(%{"type" => "error", "message" => "Unknown message type"})
        {:reply, {:text, error_response}, state}
    end
  end

  def websocket_info({:game_state_update, game_state}, state) do
    # Convert game state to spectator-friendly format
    spectator_state = format_spectator_state(game_state)
    
    message = Jason.encode!(%{
      "type" => "game_state",
      "data" => spectator_state
    })
    
    {:reply, {:text, message}, state}
  end

  def websocket_info(info, state) do
    Logger.debug("Unhandled websocket info: #{inspect(info)}")
    {:ok, state}
  end

  def terminate(reason, _req, state) do
    Logger.info("Spectator websocket terminated: #{inspect(reason)}")
    
    if state.room_id do
      SpectatorRoom.leave_spectator(state.room_id, self())
    end
    
    :ok
  end

  defp handle_join_game(game_id, state) do
    room_id = "spectator_#{game_id}"
    
    case SpectatorRoom.join_spectator(room_id, self()) do
      :ok ->
        success_response = Jason.encode!(%{
          "type" => "joined",
          "game_id" => game_id
        })
        
        Logger.info("Spectator joined game #{game_id}")
        {:reply, {:text, success_response}, %{state | game_id: game_id, room_id: room_id, authenticated: true}}
      
      {:error, reason} ->
        error_response = Jason.encode!(%{
          "type" => "error",
          "message" => "Failed to join game: #{reason}"
        })
        
        {:reply, {:text, error_response}, state}
    end
  end

  defp handle_leave_game(state) do
    if state.room_id do
      SpectatorRoom.leave_spectator(state.room_id, self())
    end
    
    success_response = Jason.encode!(%{"type" => "left"})
    {:reply, {:text, success_response}, %{state | game_id: nil, room_id: nil, authenticated: false}}
  end

  defp format_spectator_state(game_state) do
    %{
      "players" => Enum.map(game_state.players, fn {id, player} ->
        %{
          "id" => id,
          "position" => %{
            "x" => player.position.x,
            "y" => player.position.y
          },
          "health" => player.health,
          "score" => player.score,
          "status" => player.status
        }
      end),
      "game_time" => game_state.game_time,
      "match_status" => game_state.match_status,
      "timestamp" => System.system_time(:millisecond)
    }
  end
end