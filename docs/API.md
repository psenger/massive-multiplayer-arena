# Massive Multiplayer Arena - API Documentation

## Game Engine API

### GameServer

The main game server process that manages game state and player interactions.

#### Functions

- `start_link(game_id)` - Starts a new game server process
- `add_player(pid, player_data)` - Adds a player to the game
- `remove_player(pid, player_id)` - Removes a player from the game
- `update_player_input(pid, player_id, input)` - Updates player input state
- `get_game_state(pid)` - Returns current game state

#### Messages

- `{:player_joined, player_id}` - Broadcast when a player joins
- `{:player_left, player_id}` - Broadcast when a player leaves
- `{:game_state_update, state}` - Periodic game state updates
- `{:player_death, player_id, killer_id}` - When a player dies

### Player Management

#### Player Structure

```elixir
%Player{
  id: String.t(),
  position: {float(), float()},
  velocity: {float(), float()},
  health: integer(),
  max_health: integer(),
  weapon: Weapon.t(),
  power_ups: [PowerUp.t()],
  skill_rating: integer(),
  last_action_time: DateTime.t()
}
```

## Matchmaking API

### Matchmaker

Handles player matching based on skill rating and latency.

#### Functions

- `join_queue(player_data)` - Adds player to matchmaking queue
- `leave_queue(player_id)` - Removes player from queue
- `get_queue_status(player_id)` - Returns current queue position

#### Configuration

- `skill_tolerance` - Maximum skill rating difference (default: 200)
- `max_wait_time` - Maximum queue wait time in milliseconds
- `region_preference` - Preferred server region

## Spectator API

### SpectatorRoom

Manages spectators for live games.

#### Functions

- `join_as_spectator(game_id, spectator_id)` - Join game as spectator
- `leave_spectator(game_id, spectator_id)` - Leave spectator mode
- `get_spectator_count(game_id)` - Get current spectator count

### ReplaySystem

Handles game replay functionality.

#### Functions

- `start_recording(game_id)` - Begin recording game replay
- `stop_recording(game_id)` - Stop recording and save replay
- `get_replay(replay_id)` - Retrieve saved replay data
- `list_replays(filters)` - List available replays with filters

## WebSocket Events

### Client to Server

- `join_game` - Join an existing game
- `player_input` - Send player input (movement, actions)
- `chat_message` - Send chat message
- `spectate_game` - Join as spectator

### Server to Client

- `game_state` - Current game state update
- `player_joined` - Player joined notification
- `player_left` - Player left notification
- `match_found` - Matchmaking successful
- `spectator_update` - Spectator-specific updates

## Error Codes

- `GAME_FULL` - Game has reached maximum players
- `INVALID_INPUT` - Malformed input data
- `PLAYER_NOT_FOUND` - Player ID not found in game
- `GAME_NOT_FOUND` - Game ID does not exist
- `UNAUTHORIZED` - Player not authorized for action
- `RATE_LIMITED` - Too many requests from client

## Rate Limits

- Input updates: 60 per second per player
- Chat messages: 5 per minute per player
- Spectator joins: 10 per minute per IP

## Data Formats

### Position

```json
{
  "x": 100.5,
  "y": 250.0
}
```

### Input

```json
{
  "movement": {
    "up": true,
    "down": false,
    "left": false,
    "right": true
  },
  "actions": {
    "shoot": true,
    "reload": false,
    "use_power_up": false
  },
  "mouse_position": {
    "x": 150.0,
    "y": 300.0
  }
}
```