import Config

# Configure Phoenix endpoint for development
config :massive_multiplayer_arena, MassiveMultiplayerArenaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_for_massive_multiplayer_arena_game_engine",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :massive_multiplayer_arena, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Include HEEx debug annotations as HTML comments in rendered Live View markup
config :phoenix_live_view, :debug_heex_annotations, true

# Game engine development settings
config :massive_multiplayer_arena, :game_engine,
  debug_mode: true,
  log_game_events: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false