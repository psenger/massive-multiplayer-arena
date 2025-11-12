defmodule MassiveMultiplayerArena.Matchmaking.RegionManager do
  @moduledoc """
  Manages player regions and cross-region matchmaking policies.
  """

  use GenServer
  alias MassiveMultiplayerArena.Matchmaking.LatencyTracker

  @regions [:na_east, :na_west, :eu_west, :asia_pacific]
  @cross_region_latency_threshold 200

  defstruct [
    region_populations: %{},
    cross_region_policies: %{}
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def get_optimal_region(player_id) do
    GenServer.call(__MODULE__, {:get_optimal_region, player_id})
  end

  def can_match_cross_region?(player1_id, player2_id) do
    GenServer.call(__MODULE__, {:can_match_cross_region, player1_id, player2_id})
  end

  def get_region_population(region) do
    GenServer.call(__MODULE__, {:get_region_population, region})
  end

  def register_player_region(player_id, region) do
    GenServer.cast(__MODULE__, {:register_player, player_id, region})
  end

  def unregister_player(player_id) do
    GenServer.cast(__MODULE__, {:unregister_player, player_id})
  end

  def init(:ok) do
    initial_populations = @regions
                         |> Enum.map(&{&1, 0})
                         |> Enum.into(%{})
    
    initial_policies = @regions
                      |> Enum.map(&{&1, build_cross_region_policy(&1)})
                      |> Enum.into(%{})
    
    state = %__MODULE__{
      region_populations: initial_populations,
      cross_region_policies: initial_policies
    }
    
    {:ok, state}
  end

  def handle_call({:get_optimal_region, player_id}, _from, state) do
    player_region = LatencyTracker.get_region(player_id)
    player_latency = LatencyTracker.get_latency(player_id)
    
    optimal_region = if player_latency > @cross_region_latency_threshold do
      find_less_populated_region(player_region, state.region_populations)
    else
      player_region
    end
    
    {:reply, optimal_region, state}
  end

  def handle_call({:can_match_cross_region, player1_id, player2_id}, _from, state) do
    region1 = LatencyTracker.get_region(player1_id)
    region2 = LatencyTracker.get_region(player2_id)
    
    can_match = region1 == region2 or 
                LatencyTracker.compatible_latency?(player1_id, player2_id)
    
    {:reply, can_match, state}
  end

  def handle_call({:get_region_population, region}, _from, state) do
    population = Map.get(state.region_populations, region, 0)
    {:reply, population, state}
  end

  def handle_cast({:register_player, player_id, region}, state) do
    new_populations = Map.update(state.region_populations, region, 1, &(&1 + 1))
    new_state = %{state | region_populations: new_populations}
    {:noreply, new_state}
  end

  def handle_cast({:unregister_player, player_id}, state) do
    region = LatencyTracker.get_region(player_id)
    new_populations = Map.update(state.region_populations, region, 0, &max(0, &1 - 1))
    new_state = %{state | region_populations: new_populations}
    {:noreply, new_state}
  end

  defp build_cross_region_policy(region) do
    case region do
      :na_east -> [:na_west, :eu_west]
      :na_west -> [:na_east, :asia_pacific]
      :eu_west -> [:na_east, :asia_pacific]
      :asia_pacific -> [:na_west, :eu_west]
    end
  end

  defp find_less_populated_region(preferred_region, populations) do
    preferred_pop = Map.get(populations, preferred_region, 0)
    
    populations
    |> Enum.filter(fn {_region, pop} -> pop < preferred_pop end)
    |> case do
      [] -> preferred_region
      alternatives -> 
        alternatives
        |> Enum.min_by(fn {_region, pop} -> pop end)
        |> elem(0)
    end
  end
end