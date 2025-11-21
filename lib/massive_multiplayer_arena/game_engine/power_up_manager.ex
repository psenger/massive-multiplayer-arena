defmodule MassiveMultiplayerArena.GameEngine.PowerUpManager do
  @moduledoc """
  Manages power-up spawning, collection, and respawning in the game.
  """

  use GenServer
  alias MassiveMultiplayerArena.GameEngine.PowerUp

  defstruct [
    :power_ups,
    :map_width,
    :map_height,
    :next_id
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    map_width = Keyword.get(opts, :map_width, 1000)
    map_height = Keyword.get(opts, :map_height, 1000)
    
    state = %__MODULE__{
      power_ups: %{},
      map_width: map_width,
      map_height: map_height,
      next_id: 1
    }
    
    # Schedule initial power-up spawning
    Process.send_after(self(), :spawn_power_ups, 5_000)
    # Schedule periodic respawn checks
    Process.send_after(self(), :check_respawns, 1_000)
    
    {:ok, state}
  end

  def get_power_ups do
    GenServer.call(__MODULE__, :get_power_ups)
  end

  def collect_power_up(power_up_id, player) do
    GenServer.call(__MODULE__, {:collect_power_up, power_up_id, player})
  end

  def handle_call(:get_power_ups, _from, state) do
    active_power_ups = 
      state.power_ups
      |> Enum.filter(fn {_id, power_up} -> power_up.active end)
      |> Enum.into(%{})
    
    {:reply, active_power_ups, state}
  end

  def handle_call({:collect_power_up, power_up_id, player}, _from, state) do
    case Map.get(state.power_ups, power_up_id) do
      nil ->
        {:reply, {:error, :power_up_not_found}, state}
      
      power_up ->
        if PowerUp.can_collect?(power_up, player.x, player.y) do
          # Collect the power-up
          collected_power_up = PowerUp.collect(power_up)
          updated_power_ups = Map.put(state.power_ups, power_up_id, collected_power_up)
          updated_state = %{state | power_ups: updated_power_ups}
          
          # Apply effect to player
          updated_player = PowerUp.apply_effect(player, power_up)
          
          {:reply, {:ok, updated_player, power_up}, updated_state}
        else
          {:reply, {:error, :out_of_range}, state}
        end
    end
  end

  def handle_info(:spawn_power_ups, state) do
    spawn_positions = PowerUp.get_spawn_positions(state.map_width, state.map_height)
    power_up_types = PowerUp.get_power_up_types()
    
    new_power_ups = 
      spawn_positions
      |> Enum.with_index()
      |> Enum.reduce(state.power_ups, fn {{x, y}, index}, acc ->
        power_up_type = Enum.at(power_up_types, rem(index, length(power_up_types)))
        power_up = PowerUp.new(state.next_id + index, power_up_type, x, y)
        Map.put(acc, power_up.id, power_up)
      end)
    
    updated_state = %{
      state |
      power_ups: new_power_ups,
      next_id: state.next_id + length(spawn_positions)
    }
    
    {:noreply, updated_state}
  end

  def handle_info(:check_respawns, state) do
    updated_power_ups = 
      state.power_ups
      |> Enum.map(fn {id, power_up} ->
        if PowerUp.should_respawn?(power_up) do
          {id, PowerUp.respawn(power_up)}
        else
          {id, power_up}
        end
      end)
      |> Enum.into(%{})
    
    updated_state = %{state | power_ups: updated_power_ups}
    
    # Schedule next respawn check
    Process.send_after(self(), :check_respawns, 1_000)
    
    {:noreply, updated_state}
  end
end