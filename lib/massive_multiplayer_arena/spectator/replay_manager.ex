defmodule MassiveMultiplayerArena.Spectator.ReplayManager do
  use DynamicSupervisor
  alias MassiveMultiplayerArena.Spectator.ReplaySystem
  require Logger

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_replay_system(game_id) do
    child_spec = %{
      id: ReplaySystem,
      start: {ReplaySystem, :start_link, [game_id]},
      restart: :temporary,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> 
        Logger.info("Started replay system for game #{game_id}")
        {:ok, pid}
      {:error, {:already_started, pid}} -> 
        {:ok, pid}
      error -> 
        Logger.error("Failed to start replay system for game #{game_id}: #{inspect(error)}")
        error
    end
  end

  def stop_replay_system(game_id) do
    case Registry.lookup(MassiveMultiplayerArena.ReplayRegistry, game_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped replay system for game #{game_id}")
        :ok
      [] ->
        Logger.warn("Replay system for game #{game_id} not found")
        {:error, :not_found}
    end
  end

  def get_active_replays do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case Registry.keys(MassiveMultiplayerArena.ReplayRegistry, pid) do
        [game_id] -> {game_id, pid}
        [] -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  def cleanup_all_replays do
    get_active_replays()
    |> Enum.each(fn {game_id, _pid} ->
      ReplaySystem.cleanup_old_events(game_id)
    end)
    
    Logger.info("Triggered cleanup for all active replay systems")
  end

  def get_system_stats do
    active_replays = get_active_replays()
    
    stats = Enum.map(active_replays, fn {game_id, _pid} ->
      case ReplaySystem.get_replay_stats(game_id) do
        stats when is_map(stats) -> stats
        _ -> %{game_id: game_id, error: "Failed to get stats"}
      end
    end)
    
    %{
      total_active_replays: length(active_replays),
      replay_stats: stats,
      total_memory_usage: Enum.reduce(stats, 0, fn
        %{memory_usage: mem}, acc when is_integer(mem) -> acc + mem
        _, acc -> acc
      end)
    }
  end

  @impl true
  def init(_) do
    # Schedule periodic cleanup of all replay systems
    Process.send_after(self(), :periodic_cleanup, 300_000)  # 5 minutes
    
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @impl true
  def handle_info(:periodic_cleanup, state) do
    cleanup_all_replays()
    
    # Schedule next cleanup
    Process.send_after(self(), :periodic_cleanup, 300_000)
    
    {:noreply, state}
  end
end