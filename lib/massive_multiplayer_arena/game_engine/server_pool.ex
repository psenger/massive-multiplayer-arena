defmodule MassiveMultiplayerArena.GameEngine.ServerPool do
  @moduledoc """
  Manages a pool of GameServer processes to distribute load and improve performance.
  Uses a round-robin strategy for server selection.
  """

  use GenServer
  require Logger

  @pool_size 10
  @server_name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @server_name)
  end

  @doc "Gets the next available server from the pool"
  def get_server do
    GenServer.call(@server_name, :get_server)
  end

  @doc "Returns pool statistics"
  def pool_stats do
    GenServer.call(@server_name, :pool_stats)
  end

  @doc "Redistributes load across pool members"
  def rebalance_pool do
    GenServer.cast(@server_name, :rebalance)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    servers = start_server_pool()
    
    state = %{
      servers: servers,
      current_index: 0,
      pool_size: @pool_size,
      load_metrics: %{}
    }
    
    schedule_health_check()
    Logger.info("ServerPool started with #{@pool_size} servers")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_server, _from, state) do
    %{servers: servers, current_index: index, pool_size: size} = state
    
    server_pid = Enum.at(servers, index)
    next_index = rem(index + 1, size)
    
    new_state = %{state | current_index: next_index}
    {:reply, server_pid, new_state}
  end

  @impl true
  def handle_call(:pool_stats, _from, state) do
    %{servers: servers, load_metrics: metrics} = state
    
    stats = %{
      pool_size: length(servers),
      active_servers: count_alive_servers(servers),
      load_distribution: metrics,
      memory_usage: get_pool_memory_usage(servers)
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:rebalance, state) do
    %{servers: servers} = state
    
    # Remove dead servers and start new ones if needed
    alive_servers = Enum.filter(servers, &Process.alive?/1)
    needed_servers = @pool_size - length(alive_servers)
    
    new_servers = if needed_servers > 0 do
      start_additional_servers(needed_servers)
    else
      []
    end
    
    updated_servers = alive_servers ++ new_servers
    new_state = %{state | servers: updated_servers, current_index: 0}
    
    Logger.info("Pool rebalanced: #{length(updated_servers)} servers active")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    %{servers: servers, load_metrics: metrics} = state
    
    # Update load metrics for each server
    updated_metrics = Enum.reduce(servers, %{}, fn server_pid, acc ->
      case get_server_load(server_pid) do
        {:ok, load} -> Map.put(acc, server_pid, load)
        _error -> acc
      end
    end)
    
    schedule_health_check()
    new_state = %{state | load_metrics: updated_metrics}
    {:noreply, new_state}
  end

  # Private functions

  defp start_server_pool do
    Enum.map(1..@pool_size, fn i ->
      game_id = "pool_server_#{i}_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = MassiveMultiplayerArena.GameEngine.GameServer.start_link(game_id)
      pid
    end)
  end

  defp start_additional_servers(count) do
    Enum.map(1..count, fn i ->
      game_id = "pool_server_extra_#{i}_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = MassiveMultiplayerArena.GameEngine.GameServer.start_link(game_id)
      pid
    end)
  end

  defp count_alive_servers(servers) do
    Enum.count(servers, &Process.alive?/1)
  end

  defp get_pool_memory_usage(servers) do
    servers
    |> Enum.filter(&Process.alive?/1)
    |> Enum.map(fn pid ->
      case Process.info(pid, :memory) do
        {:memory, memory} -> memory
        nil -> 0
      end
    end)
    |> Enum.sum()
  end

  defp get_server_load(server_pid) do
    if Process.alive?(server_pid) do
      try do
        info = Process.info(server_pid, [:message_queue_len, :memory])
        load = %{
          queue_length: Keyword.get(info, :message_queue_len, 0),
          memory: Keyword.get(info, :memory, 0)
        }
        {:ok, load}
      rescue
        _ -> {:error, :unavailable}
      end
    else
      {:error, :dead}
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)  # 30 seconds
  end
end