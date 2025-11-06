# Massive Multiplayer Arena

A real-time multiplayer battle arena game engine built with Elixir/Phoenix, featuring dynamic matchmaking, live spectator mode, and scalable combat systems.

## Features

- Real-time combat with collision detection and physics
- Dynamic matchmaking based on skill rating and latency
- Live spectator mode with replay system and broadcast streaming
- Tournament support and player progression systems

## Installation

1. Install Elixir and Phoenix:
   ```bash
   # Install Elixir (requires Erlang)
   brew install elixir  # macOS
   # or follow official installation guide
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Set up the database:
   ```bash
   mix ecto.setup
   ```

## Usage

Start the Phoenix server:
```bash
mix phx.server
```

The game engine will be available at `http://localhost:4000`

### Development

Run tests:
```bash
mix test
```

Start interactive shell:
```bash
iex -S mix phx.server
```

## Architecture

- **Game Engine**: GenServer-based game state management
- **Matchmaking**: ETS-backed skill rating system
- **Real-time Communication**: Phoenix Channels with WebSocket transport
- **Spectator System**: Live broadcasting with replay capabilities

## License

MIT License