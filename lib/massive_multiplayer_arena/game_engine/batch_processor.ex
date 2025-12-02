defmodule MassiveMultiplayerArena.GameEngine.BatchProcessor do
  @moduledoc """
  Processes game operations in batches to improve performance and reduce overhead.
  Handles batched updates for player movements, combat actions, and state synchronization.
  """

  use GenServer
  require Logger

  @batch_size 100
  @flush_interval 16  # ~60 FPS

  defstruct [
    :game_id,
    :pending_operations,
    :batch_timer,
    :stats
  ]

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def add_operation(game_id, operation) do
    GenServer.cast(via_tuple(game_id), {:add_operation, operation})
  end

  def force_flush(game_id) do
    GenServer.call(via_tuple(game_id), :force_flush)
  end

  def get_stats(game_id) do
    GenServer.call(via_tuple(game_id), :get_stats)
  end

  # Server callbacks

  @impl true
  def init(game_id) do
    state = %__MODULE__{
      game_id: game_id,
      pending_operations: [],
      batch_timer: schedule_flush(),
      stats: %{batches_processed: 0, operations_processed: 0}
    }
    
    Logger.debug("BatchProcessor started for game #{game_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:add_operation, operation}, state) do
    %{pending_operations: pending, batch_timer: timer} = state
    
    updated_pending = [operation | pending]
    
    # Flush immediately if batch is full
    new_state = if length(updated_pending) >= @batch_size do
      Process.cancel_timer(timer)
      process_batch(%{state | pending_operations: updated_pending})
    else
      %{state | pending_operations: updated_pending}
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:force_flush, _from, state) do
    %{batch_timer: timer} = state
    Process.cancel_timer(timer)
    
    new_state = process_batch(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_info(:flush_batch, state) do
    new_state = process_batch(state)
    {:noreply, new_state}
  end

  # Private functions

  defp process_batch(%{pending_operations: []} = state) do
    %{state | batch_timer: schedule_flush()}
  end

  defp process_batch(state) do
    %{pending_operations: operations, game_id: game_id, stats: stats} = state
    
    # Group operations by type for efficient processing
    grouped_operations = group_operations(operations)
    
    # Process each group
    Enum.each(grouped_operations, fn {type, ops} ->
      process_operation_group(game_id, type, ops)
    end)
    
    # Update stats
    updated_stats = %{
      batches_processed: stats.batches_processed + 1,
      operations_processed: stats.operations_processed + length(operations)
    }
    
    Logger.debug("Processed batch of #{length(operations)} operations for game #{game_id}")
    
    %{state | 
      pending_operations: [], 
      batch_timer: schedule_flush(),
      stats: updated_stats
    }
  end

  defp group_operations(operations) do
    Enum.group_by(operations, fn
      {:player_move, _} -> :movement
      {:player_attack, _} -> :combat
      {:player_ability, _} -> :abilities
      {:projectile_update, _} -> :projectiles
      {:power_up_spawn, _} -> :power_ups
      _ -> :misc
    end)
  end

  defp process_operation_group(game_id, :movement, operations) do
    movements = Enum.map(operations, fn {:player_move, data} -> data end)
    MassiveMultiplayerArena.GameEngine.GameServer.batch_move_players(game_id, movements)
  end

  defp process_operation_group(game_id, :combat, operations) do
    attacks = Enum.map(operations, fn {:player_attack, data} -> data end)
    MassiveMultiplayerArena.GameEngine.CombatManager.batch_process_attacks(game_id, attacks)
  end

  defp process_operation_group(game_id, :abilities, operations) do
    abilities = Enum.map(operations, fn {:player_ability, data} -> data end)
    MassiveMultiplayerArena.GameEngine.GameServer.batch_use_abilities(game_id, abilities)
  end

  defp process_operation_group(game_id, :projectiles, operations) do
    updates = Enum.map(operations, fn {:projectile_update, data} -> data end)
    MassiveMultiplayerArena.GameEngine.GameServer.batch_update_projectiles(game_id, updates)
  end

  defp process_operation_group(game_id, :power_ups, operations) do
    spawns = Enum.map(operations, fn {:power_up_spawn, data} -> data end)
    MassiveMultiplayerArena.GameEngine.PowerUpManager.batch_spawn_power_ups(game_id, spawns)
  end

  defp process_operation_group(game_id, :misc, operations) do
    # Handle miscellaneous operations individually
    Enum.each(operations, fn operation ->
      MassiveMultiplayerArena.GameEngine.GameServer.handle_operation(game_id, operation)
    end)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush_batch, @flush_interval)
  end

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.GameRegistry, {:batch_processor, game_id}}}
  end
end