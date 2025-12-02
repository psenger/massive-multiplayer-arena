defmodule MassiveMultiplayerArena.GameEngine.BatchProcessor do
  @moduledoc """
  Processes game state updates in batches to improve performance
  and reduce network overhead.
  """

  use GenServer
  require Logger

  @batch_interval 16  # ~60 FPS
  @max_batch_size 100

  defstruct [
    :batch_timer,
    :pending_updates,
    :subscribers,
    :batch_count,
    :processing
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_update(update) do
    GenServer.cast(__MODULE__, {:add_update, update})
  end

  def subscribe(pid) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  def unsubscribe(pid) do
    GenServer.cast(__MODULE__, {:unsubscribe, pid})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    timer_ref = Process.send_after(self(), :process_batch, @batch_interval)
    
    state = %__MODULE__{
      batch_timer: timer_ref,
      pending_updates: [],
      subscribers: MapSet.new(),
      batch_count: 0,
      processing: false
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:add_update, update}, %{processing: true} = state) do
    # Avoid race condition by queuing updates during processing
    {:noreply, %{state | pending_updates: [update | state.pending_updates]}}
  end

  def handle_cast({:add_update, update}, state) do
    new_updates = [update | state.pending_updates]
    
    # Process immediately if batch is full
    if length(new_updates) >= @max_batch_size do
      Process.cancel_timer(state.batch_timer)
      send(self(), :process_batch)
      {:noreply, %{state | pending_updates: new_updates}}
    else
      {:noreply, %{state | pending_updates: new_updates}}
    end
  end

  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    new_subscribers = MapSet.put(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      pending_updates: length(state.pending_updates),
      subscribers: MapSet.size(state.subscribers),
      batch_count: state.batch_count,
      processing: state.processing
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    new_state = process_current_batch(state)
    
    # Schedule next batch
    timer_ref = Process.send_after(self(), :process_batch, @batch_interval)
    
    {:noreply, %{new_state | batch_timer: timer_ref, processing: false}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  # Private Functions

  defp process_current_batch(%{pending_updates: []} = state) do
    state
  end

  defp process_current_batch(state) do
    %{state | processing: true}
    |> apply_batch_processing()
    |> broadcast_to_subscribers()
    |> update_batch_stats()
  end

  defp apply_batch_processing(state) do
    try do
      # Reverse to maintain chronological order
      updates = Enum.reverse(state.pending_updates)
      
      # Group and deduplicate updates
      processed_batch = 
        updates
        |> group_updates_by_entity()
        |> merge_duplicate_updates()
        |> validate_updates()
      
      %{state | pending_updates: [], processed_batch: processed_batch}
    rescue
      error ->
        Logger.error("Batch processing failed: #{inspect(error)}")
        %{state | pending_updates: [], processed_batch: []}
    end
  end

  defp group_updates_by_entity(updates) do
    Enum.group_by(updates, fn update ->
      Map.get(update, :entity_id, :global)
    end)
  end

  defp merge_duplicate_updates(grouped_updates) do
    Enum.map(grouped_updates, fn {entity_id, updates} ->
      merged_update = Enum.reduce(updates, %{}, fn update, acc ->
        Map.merge(acc, update)
      end)
      
      Map.put(merged_update, :entity_id, entity_id)
    end)
  end

  defp validate_updates(updates) do
    Enum.filter(updates, fn update ->
      is_map(update) and Map.has_key?(update, :entity_id)
    end)
  end

  defp broadcast_to_subscribers(%{processed_batch: []} = state) do
    state
  end

  defp broadcast_to_subscribers(state) do
    batch_message = {:batch_update, state.processed_batch}
    
    # Safely broadcast to all subscribers
    Enum.each(state.subscribers, fn subscriber_pid ->
      if Process.alive?(subscriber_pid) do
        send(subscriber_pid, batch_message)
      end
    end)
    
    state
  end

  defp update_batch_stats(state) do
    %{state | batch_count: state.batch_count + 1}
  end
end