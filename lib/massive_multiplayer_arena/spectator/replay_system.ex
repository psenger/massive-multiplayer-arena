defmodule MassiveMultiplayerArena.Spectator.ReplaySystem do
  @moduledoc """
  Handles recording and playback of game replays for spectator mode.
  Records game state snapshots at regular intervals for later playback.
  """

  use GenServer
  alias MassiveMultiplayerArena.GameEngine.GameState
  require Logger

  @snapshot_interval 100  # milliseconds
  @max_replay_duration 30 * 60 * 1000  # 30 minutes in milliseconds

  defstruct [
    :game_id,
    :recording,
    :snapshots,
    :start_time,
    :last_snapshot_time,
    :timer_ref
  ]

  ## Client API

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def start_recording(game_id) do
    GenServer.call(via_tuple(game_id), :start_recording)
  end

  def stop_recording(game_id) do
    GenServer.call(via_tuple(game_id), :stop_recording)
  end

  def record_snapshot(game_id, %GameState{} = game_state) do
    GenServer.cast(via_tuple(game_id), {:record_snapshot, game_state})
  end

  def get_replay_data(game_id) do
    GenServer.call(via_tuple(game_id), :get_replay_data)
  end

  def get_snapshot_at_time(game_id, timestamp) do
    GenServer.call(via_tuple(game_id), {:get_snapshot_at_time, timestamp})
  end

  ## Server Callbacks

  @impl true
  def init(game_id) do
    state = %__MODULE__{
      game_id: game_id,
      recording: false,
      snapshots: [],
      start_time: nil,
      last_snapshot_time: nil,
      timer_ref: nil
    }
    
    Logger.info("Replay system started for game #{game_id}")
    {:ok, state}
  end

  @impl true
  def handle_call(:start_recording, _from, state) do
    if state.recording do
      {:reply, {:error, :already_recording}, state}
    else
      now = System.monotonic_time(:millisecond)
      timer_ref = Process.send_after(self(), :cleanup_old_snapshots, @max_replay_duration)
      
      new_state = %{state |
        recording: true,
        start_time: now,
        last_snapshot_time: now,
        timer_ref: timer_ref
      }
      
      Logger.info("Started recording replay for game #{state.game_id}")
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop_recording, _from, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end
    
    new_state = %{state | recording: false, timer_ref: nil}
    Logger.info("Stopped recording replay for game #{state.game_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_replay_data, _from, state) do
    replay_data = %{
      game_id: state.game_id,
      start_time: state.start_time,
      snapshots: Enum.reverse(state.snapshots),
      duration: get_replay_duration(state)
    }
    
    {:reply, replay_data, state}
  end

  @impl true
  def handle_call({:get_snapshot_at_time, timestamp}, _from, state) do
    snapshot = find_snapshot_at_time(state.snapshots, timestamp)
    {:reply, snapshot, state}
  end

  @impl true
  def handle_cast({:record_snapshot, game_state}, %{recording: false} = state) do
    # Ignore snapshots when not recording
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_snapshot, game_state}, state) do
    now = System.monotonic_time(:millisecond)
    
    # Only record if enough time has passed since last snapshot
    if now - state.last_snapshot_time >= @snapshot_interval do
      snapshot = create_snapshot(game_state, now - state.start_time)
      new_snapshots = [snapshot | state.snapshots]
      
      # Limit the number of snapshots to prevent memory issues
      trimmed_snapshots = trim_snapshots(new_snapshots)
      
      new_state = %{state |
        snapshots: trimmed_snapshots,
        last_snapshot_time: now
      }
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_old_snapshots, state) do
    # Clean up snapshots older than max duration
    cutoff_time = System.monotonic_time(:millisecond) - @max_replay_duration
    
    new_snapshots = Enum.filter(state.snapshots, fn snapshot ->
      snapshot.absolute_time >= cutoff_time
    end)
    
    new_state = %{state | snapshots: new_snapshots}
    
    # Schedule next cleanup
    timer_ref = Process.send_after(self(), :cleanup_old_snapshots, @max_replay_duration)
    new_state = %{new_state | timer_ref: timer_ref}
    
    {:noreply, new_state}
  end

  ## Private Functions

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.Registry, {__MODULE__, game_id}}}
  end

  defp create_snapshot(game_state, relative_time) do
    %{
      relative_time: relative_time,
      absolute_time: System.monotonic_time(:millisecond),
      players: serialize_players(game_state.players),
      projectiles: serialize_projectiles(game_state.projectiles),
      game_status: game_state.status,
      score: game_state.score
    }
  end

  defp serialize_players(players) do
    Enum.map(players, fn {player_id, player} ->
      %{
        id: player_id,
        position: player.position,
        velocity: player.velocity,
        health: player.health,
        status: player.status
      }
    end)
  end

  defp serialize_projectiles(projectiles) do
    Enum.map(projectiles, fn projectile ->
      %{
        id: projectile.id,
        position: projectile.position,
        velocity: projectile.velocity,
        owner_id: projectile.owner_id
      }
    end)
  end

  defp find_snapshot_at_time(snapshots, timestamp) do
    snapshots
    |> Enum.find(fn snapshot -> snapshot.relative_time <= timestamp end)
  end

  defp trim_snapshots(snapshots) do
    # Keep only the last 10000 snapshots (about 16.7 minutes at 100ms intervals)
    Enum.take(snapshots, 10000)
  end

  defp get_replay_duration(state) do
    if state.start_time do
      System.monotonic_time(:millisecond) - state.start_time
    else
      0
    end
  end
end