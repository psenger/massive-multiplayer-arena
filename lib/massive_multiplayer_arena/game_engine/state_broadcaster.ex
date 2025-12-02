defmodule MassiveMultiplayerArena.GameEngine.StateBroadcaster do
  @moduledoc """
  Handles broadcasting of game state updates to connected clients
  with optimized batching and compression.
  """

  use GenServer
  alias MassiveMultiplayerArena.GameEngine.{BatchProcessor, GameState}
  require Logger

  defstruct [
    :game_id,
    :clients,
    :compression_enabled,
    :broadcast_stats
  ]

  # Client API

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def add_client(game_id, client_pid, client_info \\ %{}) do
    GenServer.cast(via_tuple(game_id), {:add_client, client_pid, client_info})
  end

  def remove_client(game_id, client_pid) do
    GenServer.cast(via_tuple(game_id), {:remove_client, client_pid})
  end

  def broadcast_state(game_id, game_state) do
    GenServer.cast(via_tuple(game_id), {:broadcast_state, game_state})
  end

  def broadcast_event(game_id, event) do
    GenServer.cast(via_tuple(game_id), {:broadcast_event, event})
  end

  def get_client_count(game_id) do
    try do
      GenServer.call(via_tuple(game_id), :get_client_count, 1000)
    catch
      :exit, _ -> 0
    end
  end

  def get_stats(game_id) do
    GenServer.call(via_tuple(game_id), :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(game_id) do
    # Subscribe to batch processor
    BatchProcessor.subscribe(self())
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      game_id: game_id,
      clients: %{},
      compression_enabled: true,
      broadcast_stats: %{
        messages_sent: 0,
        bytes_sent: 0,
        clients_disconnected: 0
      }
    }

    Logger.info("State broadcaster started for game #{game_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:add_client, client_pid, client_info}, state) do
    Process.monitor(client_pid)
    
    client_data = Map.merge(client_info, %{
      connected_at: System.system_time(:millisecond),
      messages_sent: 0
    })
    
    new_clients = Map.put(state.clients, client_pid, client_data)
    
    Logger.debug("Client #{inspect(client_pid)} connected to game #{state.game_id}")
    {:noreply, %{state | clients: new_clients}}
  end

  def handle_cast({:remove_client, client_pid}, state) do
    new_clients = Map.delete(state.clients, client_pid)
    Logger.debug("Client #{inspect(client_pid)} removed from game #{state.game_id}")
    {:noreply, %{state | clients: new_clients}}
  end

  def handle_cast({:broadcast_state, game_state}, state) do
    message = {:game_state_update, game_state}
    new_state = broadcast_to_clients(state, message)
    {:noreply, new_state}
  end

  def handle_cast({:broadcast_event, event}, state) do
    message = {:game_event, event}
    new_state = broadcast_to_clients(state, message)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_client_count, _from, state) do
    {:reply, map_size(state.clients), state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.broadcast_stats, %{
      client_count: map_size(state.clients),
      game_id: state.game_id,
      compression_enabled: state.compression_enabled
    })
    {:reply, stats, state}
  end

  @impl true
  def handle_info({:batch_update, batch}, state) do
    # Process batched updates from BatchProcessor
    message = {:batch_state_update, batch}
    new_state = broadcast_to_clients(state, message)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Map.get(state.clients, pid) do
      nil ->
        {:noreply, state}
      
      _client_data ->
        new_clients = Map.delete(state.clients, pid)
        new_stats = update_in(state.broadcast_stats.clients_disconnected, &(&1 + 1))
        
        Logger.debug("Client #{inspect(pid)} disconnected from game #{state.game_id}: #{inspect(reason)}")
        {:noreply, %{state | clients: new_clients, broadcast_stats: %{state.broadcast_stats | clients_disconnected: new_stats}}}
    end
  end

  @impl true
  def terminate(reason, state) do
    BatchProcessor.unsubscribe(self())
    Logger.info("State broadcaster for game #{state.game_id} terminating: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.GameRegistry, {"broadcaster", game_id}}}
  end

  defp broadcast_to_clients(state, message) do
    if map_size(state.clients) == 0 do
      state
    else
      encoded_message = encode_message(message, state.compression_enabled)
      message_size = byte_size(encoded_message)
      
      {successful_sends, failed_sends} = 
        state.clients
        |> Enum.map(fn {client_pid, client_data} ->
          send_to_client(client_pid, encoded_message, client_data)
        end)
        |> Enum.split_with(fn {success, _pid, _client_data} -> success end)
      
      # Update client data for successful sends
      updated_clients = 
        successful_sends
        |> Enum.reduce(state.clients, fn {_success, pid, client_data}, acc ->
          updated_data = %{client_data | messages_sent: client_data.messages_sent + 1}
          Map.put(acc, pid, updated_data)
        end)
      
      # Remove failed clients
      cleaned_clients = 
        failed_sends
        |> Enum.reduce(updated_clients, fn {_success, pid, _client_data}, acc ->
          Map.delete(acc, pid)
        end)
      
      # Update broadcast stats
      new_stats = %{
        state.broadcast_stats |
        messages_sent: state.broadcast_stats.messages_sent + length(successful_sends),
        bytes_sent: state.broadcast_stats.bytes_sent + (message_size * length(successful_sends))
      }
      
      %{state | clients: cleaned_clients, broadcast_stats: new_stats}
    end
  end

  defp send_to_client(client_pid, encoded_message, client_data) do
    try do
      if Process.alive?(client_pid) do
        send(client_pid, {:broadcast_message, encoded_message})
        {true, client_pid, client_data}
      else
        {false, client_pid, client_data}
      end
    catch
      :error, _ -> {false, client_pid, client_data}
    end
  end

  defp encode_message(message, compression_enabled) do
    encoded = :erlang.term_to_binary(message)
    
    if compression_enabled and byte_size(encoded) > 1024 do
      :zlib.compress(encoded)
    else
      encoded
    end
  end
end