defmodule MassiveMultiplayerArena.Spectator.WebsocketHandler do
  @behaviour :cowboy_websocket

  alias MassiveMultiplayerArena.Spectator.SpectatorRoom
  require Logger

  defstruct [
    :spectator_id,
    :game_id,
    :joined_room,
    :ping_timer,
    :connection_state
  ]

  def init(req, _state) do
    game_id = :cowboy_req.binding(:game_id, req)
    spectator_id = generate_spectator_id()
    
    state = %__MODULE__{
      spectator_id: spectator_id,
      game_id: game_id,
      joined_room: false,
      ping_timer: nil,
      connection_state: :connecting
    }
    
    {:cowboy_websocket, req, state, %{idle_timeout: 30_000}}
  end

  def websocket_init(state) do
    # Attempt to join spectator room with retry logic
    case attempt_join_room(state, 3) do
      {:ok, new_state} ->
        ping_timer = schedule_ping()
        final_state = %{new_state | 
          joined_room: true, 
          ping_timer: ping_timer,
          connection_state: :connected
        }
        
        welcome_msg = Jason.encode!(%{
          type: "welcome",
          spectator_id: state.spectator_id,
          game_id: state.game_id
        })
        
        {:reply, {:text, welcome_msg}, final_state}
        
      {:error, reason} ->
        Logger.warning("Failed to join spectator room: #{inspect(reason)}")
        error_msg = Jason.encode!(%{
          type: "error",
          reason: "Failed to join spectator room"
        })
        
        {:reply, [{:text, error_msg}, :close], state}
    end
  end

  def websocket_handle({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, %{"type" => "ping"}} ->
        pong_msg = Jason.encode!(%{type: "pong", timestamp: System.system_time(:millisecond)})
        {:reply, {:text, pong_msg}, state}
        
      {:ok, %{"type" => "spectator_count_request"}} ->
        count = SpectatorRoom.get_spectator_count(state.game_id)
        response = Jason.encode!(%{type: "spectator_count", count: count})
        {:reply, {:text, response}, state}
        
      {:error, _} ->
        Logger.warning("Invalid JSON message received")
        {:ok, state}
        
      _ ->
        {:ok, state}
    end
  end

  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  def websocket_info({:send_game_state, game_state}, state) do
    message = Jason.encode!(%{
      type: "game_state",
      data: game_state,
      timestamp: System.system_time(:millisecond)
    })
    
    {:reply, {:text, message}, state}
  end

  def websocket_info(:ping, state) do
    ping_msg = Jason.encode!(%{type: "ping", timestamp: System.system_time(:millisecond)})
    new_timer = schedule_ping()
    {:reply, {:text, ping_msg}, %{state | ping_timer: new_timer}}
  end

  def websocket_info(info, state) do
    Logger.debug("Unhandled websocket info: #{inspect(info)}")
    {:ok, state}
  end

  def terminate(reason, _req, state) do
    Logger.info("WebSocket terminating: #{inspect(reason)}")
    
    if state.ping_timer do
      Process.cancel_timer(state.ping_timer)
    end
    
    # Only attempt to leave if we successfully joined
    if state.joined_room do
      # Use async leave to prevent blocking termination
      Task.start(fn ->
        try do
          SpectatorRoom.leave_spectator(state.game_id, state.spectator_id)
        rescue
          error ->
            Logger.warning("Error leaving spectator room during termination: #{inspect(error)}")
        end
      end)
    end
    
    :ok
  end

  def send_game_state(pid, game_state) when is_pid(pid) do
    send(pid, {:send_game_state, game_state})
  end

  defp attempt_join_room(state, retries_left) when retries_left > 0 do
    case SpectatorRoom.join_spectator(state.game_id, state.spectator_id, self()) do
      :ok ->
        {:ok, state}
        
      {:error, :operation_pending} ->
        # Wait a bit and retry
        :timer.sleep(100)
        attempt_join_room(state, retries_left - 1)
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp attempt_join_room(_state, 0) do
    {:error, :max_retries_exceeded}
  end

  defp schedule_ping do
    Process.send_after(self(), :ping, 15_000)
  end

  defp generate_spectator_id do
    "spectator_" <> :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end