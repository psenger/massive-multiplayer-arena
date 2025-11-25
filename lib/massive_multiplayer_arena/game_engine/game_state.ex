defmodule MassiveMultiplayerArena.GameEngine.GameState do
  @moduledoc """
  Manages the complete state of a game instance with optimized updates.
  """

  alias MassiveMultiplayerArena.GameEngine.{Player, Projectile, PowerUp}

  defstruct [
    :game_id,
    :players,
    :projectiles,
    :power_ups,
    :tick_count,
    :started_at,
    :last_update,
    :delta_cache,
    :update_queue
  ]

  @type t :: %__MODULE__{
    game_id: String.t(),
    players: %{String.t() => Player.t()},
    projectiles: %{String.t() => Projectile.t()},
    power_ups: %{String.t() => PowerUp.t()},
    tick_count: non_neg_integer(),
    started_at: DateTime.t(),
    last_update: DateTime.t(),
    delta_cache: map(),
    update_queue: list()
  }

  def new(game_id) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      game_id: game_id,
      players: %{},
      projectiles: %{},
      power_ups: %{},
      tick_count: 0,
      started_at: now,
      last_update: now,
      delta_cache: %{},
      update_queue: []
    }
  end

  def add_player(state, player) do
    new_players = Map.put(state.players, player.id, player)
    delta = %{type: :player_joined, player_id: player.id, player: player}
    
    state
    |> Map.put(:players, new_players)
    |> queue_update(delta)
  end

  def update_player(state, player_id, updates) do
    case Map.get(state.players, player_id) do
      nil -> state
      player ->
        updated_player = struct(player, updates)
        new_players = Map.put(state.players, player_id, updated_player)
        
        # Only create delta for changed fields
        changed_fields = get_changed_fields(player, updated_player)
        
        if changed_fields != %{} do
          delta = %{
            type: :player_updated,
            player_id: player_id,
            changes: changed_fields
          }
          
          state
          |> Map.put(:players, new_players)
          |> queue_update(delta)
        else
          Map.put(state, :players, new_players)
        end
    end
  end

  def remove_player(state, player_id) do
    case Map.get(state.players, player_id) do
      nil -> state
      _player ->
        new_players = Map.delete(state.players, player_id)
        delta = %{type: :player_left, player_id: player_id}
        
        state
        |> Map.put(:players, new_players)
        |> queue_update(delta)
    end
  end

  def add_projectile(state, projectile) do
    new_projectiles = Map.put(state.projectiles, projectile.id, projectile)
    delta = %{type: :projectile_created, projectile: projectile}
    
    state
    |> Map.put(:projectiles, new_projectiles)
    |> queue_update(delta)
  end

  def update_projectile(state, projectile_id, updates) do
    case Map.get(state.projectiles, projectile_id) do
      nil -> state
      projectile ->
        updated_projectile = struct(projectile, updates)
        new_projectiles = Map.put(state.projectiles, projectile_id, updated_projectile)
        
        changed_fields = get_changed_fields(projectile, updated_projectile)
        
        if changed_fields != %{} do
          delta = %{
            type: :projectile_updated,
            projectile_id: projectile_id,
            changes: changed_fields
          }
          
          state
          |> Map.put(:projectiles, new_projectiles)
          |> queue_update(delta)
        else
          Map.put(state, :projectiles, new_projectiles)
        end
    end
  end

  def remove_projectile(state, projectile_id) do
    case Map.get(state.projectiles, projectile_id) do
      nil -> state
      _projectile ->
        new_projectiles = Map.delete(state.projectiles, projectile_id)
        delta = %{type: :projectile_destroyed, projectile_id: projectile_id}
        
        state
        |> Map.put(:projectiles, new_projectiles)
        |> queue_update(delta)
    end
  end

  def tick(state) do
    now = DateTime.utc_now()
    
    state
    |> Map.put(:tick_count, state.tick_count + 1)
    |> Map.put(:last_update, now)
  end

  def get_delta_updates(state) do
    updates = Enum.reverse(state.update_queue)
    compressed_updates = compress_updates(updates)
    
    {compressed_updates, %{state | update_queue: []}}
  end

  def get_full_state(state) do
    %{
      game_id: state.game_id,
      players: state.players,
      projectiles: state.projectiles,
      power_ups: state.power_ups,
      tick_count: state.tick_count,
      timestamp: DateTime.to_unix(state.last_update, :millisecond)
    }
  end

  # Private functions

  defp queue_update(state, delta) do
    new_queue = [delta | state.update_queue]
    Map.put(state, :update_queue, new_queue)
  end

  defp get_changed_fields(old_struct, new_struct) do
    old_map = Map.from_struct(old_struct)
    new_map = Map.from_struct(new_struct)
    
    old_map
    |> Enum.reduce(%{}, fn {key, old_value}, acc ->
      case Map.get(new_map, key) do
        ^old_value -> acc
        new_value -> Map.put(acc, key, new_value)
      end
    end)
  end

  defp compress_updates(updates) do
    updates
    |> Enum.group_by(fn update ->
      case update do
        %{type: :player_updated, player_id: id} -> {:player, id}
        %{type: :projectile_updated, projectile_id: id} -> {:projectile, id}
        _ -> :other
      end
    end)
    |> Enum.flat_map(fn
      {:other, other_updates} -> other_updates
      {{:player, player_id}, player_updates} ->
        merged_changes = merge_player_changes(player_updates)
        [%{type: :player_updated, player_id: player_id, changes: merged_changes}]
      {{:projectile, projectile_id}, projectile_updates} ->
        merged_changes = merge_projectile_changes(projectile_updates)
        [%{type: :projectile_updated, projectile_id: projectile_id, changes: merged_changes}]
    end)
  end

  defp merge_player_changes(updates) do
    Enum.reduce(updates, %{}, fn %{changes: changes}, acc ->
      Map.merge(acc, changes)
    end)
  end

  defp merge_projectile_changes(updates) do
    Enum.reduce(updates, %{}, fn %{changes: changes}, acc ->
      Map.merge(acc, changes)
    end)
  end
end