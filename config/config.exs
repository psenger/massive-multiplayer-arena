import Config

config :massive_multiplayer_arena, MassiveMultiplayerArenaWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: MassiveMultiplayerArenaWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: MassiveMultiplayerArena.PubSub,
  live_view: [signing_salt: "YourSigningSalt"]

config :massive_multiplayer_arena,
  ecto_repos: [],
  generators: [context_app: false]

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Game engine configuration
config :massive_multiplayer_arena, :game_engine,
  tick_rate: 60,
  max_players_per_match: 10,
  match_timeout: 600_000,
  physics_steps_per_tick: 4

# Matchmaking configuration
config :massive_multiplayer_arena, :matchmaking,
  queue_timeout: 30_000,
  skill_variance_threshold: 200,
  latency_threshold: 150,
  min_players: 2,
  max_players: 10

# Clustering configuration
config :libcluster,
  topologies: [
    arena_cluster: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: []]
    ]
  ]

import_config "#{config_env()}.exs"