import Config

config :massive_multiplayer_arena, MassiveMultiplayerArenaWeb.Endpoint,
  http: [port: 4000],
  url: [host: "example.com", port: 80],
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :logger, level: :info

config :phoenix, :serve_endpoints, true

# Game engine production tuning
config :massive_multiplayer_arena, :game_engine,
  tick_rate: 60,
  max_players_per_match: 20,
  match_timeout: 1_200_000,
  physics_steps_per_tick: 2

# Matchmaking production settings
config :massive_multiplayer_arena, :matchmaking,
  queue_timeout: 45_000,
  skill_variance_threshold: 300,
  latency_threshold: 200,
  min_players: 4,
  max_players: 20

# Production clustering
config :libcluster,
  topologies: [
    arena_cluster: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "arena",
        kubernetes_selector: "app=massive-multiplayer-arena",
        polling_interval: 10_000
      ]
    ]
  ]