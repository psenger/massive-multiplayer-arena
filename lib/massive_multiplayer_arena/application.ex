defmodule MassiveMultiplayerArena.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for game processes
      {Registry, keys: :unique, name: MassiveMultiplayerArena.GameRegistry},
      
      # Game server pool for load distribution
      MassiveMultiplayerArena.GameEngine.ServerPool,
      
      # Matchmaking system
      MassiveMultiplayerArena.Matchmaking.Matchmaker,
      MassiveMultiplayerArena.Matchmaking.RegionManager,
      
      # Registry for spectator processes
      {Registry, keys: :unique, name: MassiveMultiplayerArena.SpectatorRegistry},

      # ReplayManager (DynamicSupervisor for replay systems)
      MassiveMultiplayerArena.Spectator.ReplayManager,

      # Task supervisor for async operations
      {Task.Supervisor, name: MassiveMultiplayerArena.TaskSupervisor},
      
      # Dynamic supervisor for game instances
      {DynamicSupervisor, 
       strategy: :one_for_one, 
       name: MassiveMultiplayerArena.GameSupervisor,
       max_children: 1000}
    ]

    opts = [strategy: :one_for_one, name: MassiveMultiplayerArena.Supervisor]
    Supervisor.start_link(children, opts)
  end
end