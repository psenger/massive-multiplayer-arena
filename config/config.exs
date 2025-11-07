import Config

# Configure Phoenix endpoint
config :massive_multiplayer_arena, MassiveMultiplayerArenaWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: MassiveMultiplayerArenaWeb.ErrorHTML, json: MassiveMultiplayerArenaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MassiveMultiplayerArena.PubSub,
  live_view: [signing_salt: "game_arena_salt"]

# Configure logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :game_id, :player_id]

# Configure Phoenix generators
config :phoenix, :json_library, Jason

# Game engine configuration
config :massive_multiplayer_arena, :game_engine,
  tick_rate: 60,
  max_players_per_game: 10,
  game_timeout: 600_000

# Matchmaking configuration
config :massive_multiplayer_arena, :matchmaking,
  max_skill_difference: 200,
  matchmaking_timeout: 30_000,
  min_players: 2

# Import environment specific config
import_config "#{config_env()}.exs"