defmodule MassiveMultiplayerArena.Application do
  @moduledoc """
  The MassiveMultiplayerArena Application callback.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      MassiveMultiplayerArenaWeb.Telemetry,
      # Start the Ecto repository
      MassiveMultiplayerArena.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: MassiveMultiplayerArena.PubSub},
      # Start Finch
      {Finch, name: MassiveMultiplayerArena.Finch},
      # Start the Endpoint (http/https)
      MassiveMultiplayerArenaWeb.Endpoint,
      # Game Engine Supervisors
      MassiveMultiplayerArena.GameEngine.Supervisor,
      # Matchmaking System
      MassiveMultiplayerArena.Matchmaking.Supervisor,
      # Spectator System
      MassiveMultiplayerArena.Spectator.Supervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MassiveMultiplayerArena.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MassiveMultiplayerArenaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end