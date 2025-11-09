defmodule MassiveMultiplayerArena.GameEngine.GameState do
  @moduledoc """
  Manages the overall state of a game instance including players, arena, and game status.
  """

  alias MassiveMultiplayerArena.GameEngine.Player

  defstruct [
    :game_id,
    :players,
    :arena_bounds,
    :status,
    :started_at,
    :last_update,
    :tick_count
  ]

  @type status :: :waiting | :active | :finished

  @type t :: %__MODULE__{
    game_id: String.t(),
    players: %{String.t() => Player.t()},
    arena_bounds: %{width: integer(), height: integer()},
    status: status(),
    started_at: DateTime.t() | nil,
    last_update: DateTime.t(),
    tick_count: integer()
  }

  @doc """
  Creates a new game state.
  """
  @spec new(String.t()) :: t()
  def new(game_id) do
    %__MODULE__{
      game_id: game_id,
      players: %{},
      arena_bounds: %{width: 1000, height: 1000},
      status: :waiting,
      started_at: nil,
      last_update: DateTime.utc_now(),
      tick_count: 0
    }
  end

  @doc """
  Adds a player to the game.
  """
  @spec add_player(t(), Player.t()) :: t()
  def add_player(%__MODULE__{players: players} = state, %Player{} = player) do
    updated_players = Map.put(players, player.id, player)
    %{state | players: updated_players, last_update: DateTime.utc_now()}
  end

  @doc """
  Removes a player from the game.
  """
  @spec remove_player(t(), String.t()) :: t()
  def remove_player(%__MODULE__{players: players} = state, player_id) do
    updated_players = Map.delete(players, player_id)
    %{state | players: updated_players, last_update: DateTime.utc_now()}
  end

  @doc """
  Updates a specific player in the game state.
  """
  @spec update_player(t(), String.t(), Player.t()) :: t()
  def update_player(%__MODULE__{players: players} = state, player_id, updated_player) do
    case Map.has_key?(players, player_id) do
      true ->
        updated_players = Map.put(players, player_id, updated_player)
        %{state | players: updated_players, last_update: DateTime.utc_now()}
      false ->
        state
    end
  end

  @doc """
  Starts the game if enough players are present.
  """
  @spec start_game(t()) :: t()
  def start_game(%__MODULE__{status: :waiting, players: players} = state) when map_size(players) >= 2 do
    %{state | status: :active, started_at: DateTime.utc_now(), last_update: DateTime.utc_now()}
  end
  def start_game(%__MODULE__{} = state), do: state

  @doc """
  Increments the game tick counter.
  """
  @spec tick(t()) :: t()
  def tick(%__MODULE__{tick_count: count} = state) do
    %{state | tick_count: count + 1, last_update: DateTime.utc_now()}
  end

  @doc """
  Gets all alive players.
  """
  @spec alive_players(t()) :: [Player.t()]
  def alive_players(%__MODULE__{players: players}) do
    players
    |> Map.values()
    |> Enum.filter(&Player.alive?/1)
  end

  @doc """
  Checks if game should end (only one or no players alive).
  """
  @spec should_end?(t()) :: boolean()
  def should_end?(%__MODULE__{} = state) do
    alive_count = state |> alive_players() |> length()
    alive_count <= 1 and state.status == :active
  end
end