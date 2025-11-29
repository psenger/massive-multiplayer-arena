# Deployment Guide

## Environment Setup

### Prerequisites

- Elixir 1.14+
- Erlang/OTP 25+
- PostgreSQL 14+
- Redis 6.2+
- Docker & Docker Compose (for containerized deployment)

### Development Environment

1. **Clone Repository**
   ```bash
   git clone https://github.com/yourorg/massive-multiplayer-arena.git
   cd massive-multiplayer-arena
   ```

2. **Install Dependencies**
   ```bash
   mix deps.get
   mix deps.compile
   ```

3. **Database Setup**
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

4. **Start Development Server**
   ```bash
   mix phx.server
   ```

## Production Deployment

### Docker Deployment

1. **Build Production Image**
   ```dockerfile
   FROM elixir:1.14-alpine AS builder
   
   WORKDIR /app
   COPY mix.exs mix.lock ./
   RUN mix deps.get --only=prod
   
   COPY . .
   RUN mix compile
   RUN mix release
   
   FROM alpine:3.16
   RUN apk add --no-cache openssl ncurses-libs
   
   WORKDIR /app
   COPY --from=builder /app/_build/prod/rel/massive_multiplayer_arena ./
   
   CMD ["./bin/massive_multiplayer_arena", "start"]
   ```

2. **Docker Compose Configuration**
   ```yaml
   version: '3.8'
   
   services:
     app:
       build: .
       ports:
         - "4000:4000"
       environment:
         - DATABASE_URL=postgresql://user:pass@db:5432/mma_prod
         - REDIS_URL=redis://redis:6379
         - SECRET_KEY_BASE=${SECRET_KEY_BASE}
       depends_on:
         - db
         - redis
   
     db:
       image: postgres:14-alpine
       environment:
         - POSTGRES_DB=mma_prod
         - POSTGRES_USER=user
         - POSTGRES_PASSWORD=pass
       volumes:
         - postgres_data:/var/lib/postgresql/data
   
     redis:
       image: redis:6.2-alpine
       volumes:
         - redis_data:/data
   
   volumes:
     postgres_data:
     redis_data:
   ```

### Kubernetes Deployment

1. **Application Deployment**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: mma-app
   spec:
     replicas: 3
     selector:
       matchLabels:
         app: mma-app
     template:
       metadata:
         labels:
           app: mma-app
       spec:
         containers:
         - name: mma-app
           image: mma:latest
           ports:
           - containerPort: 4000
           env:
           - name: DATABASE_URL
             valueFrom:
               secretKeyRef:
                 name: mma-secrets
                 key: database-url
           resources:
             requests:
               memory: "512Mi"
               cpu: "250m"
             limits:
               memory: "1Gi"
               cpu: "500m"
   ```

2. **Load Balancer Service**
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: mma-service
   spec:
     selector:
       app: mma-app
     ports:
     - port: 80
       targetPort: 4000
     type: LoadBalancer
   ```

## Configuration

### Environment Variables

- `SECRET_KEY_BASE` - Phoenix secret key (required)
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string
- `PORT` - HTTP server port (default: 4000)
- `GAME_TICK_RATE` - Game simulation frequency (default: 60)
- `MAX_PLAYERS_PER_GAME` - Player limit per game (default: 20)
- `MATCHMAKING_TIMEOUT` - Max queue wait time in ms (default: 30000)
- `SPECTATOR_LIMIT` - Max spectators per game (default: 100)

### Production Settings

1. **config/prod.exs**
   ```elixir
   config :massive_multiplayer_arena, MassiveMultiplayerArenaWeb.Endpoint,
     url: [host: "your-domain.com", port: 80],
     cache_static_manifest: "priv/static/cache_manifest.json",
     server: true
   
   config :massive_multiplayer_arena,
     game_tick_rate: 60,
     max_players_per_game: 20,
     spectator_limit: 100
   ```

## Monitoring & Logging

### Health Checks

- **HTTP Endpoint**: `GET /health`
- **WebSocket Status**: `GET /ws/health`
- **Game Server Status**: `GET /games/health`

### Metrics Collection

1. **Prometheus Configuration**
   ```elixir
   # In application.ex
   children = [
     MassiveMultiplayerArena.PromEx,
     # ... other children
   ]
   ```

2. **Custom Metrics**
   - `mma_active_games_total` - Number of active game sessions
   - `mma_players_online_total` - Current online player count
   - `mma_matchmaking_duration_seconds` - Queue wait times
   - `mma_game_tick_duration_seconds` - Game loop performance

### Log Management

1. **Structured Logging**
   ```elixir
   config :logger, :console,
     format: "$time $metadata[$level] $message\n",
     metadata: [:request_id, :game_id, :player_id]
   ```

2. **Log Aggregation**
   - Use ELK stack (Elasticsearch, Logstash, Kibana)
   - Configure log shipping with Filebeat
   - Set up alerts for error patterns

## Scaling Considerations

### Vertical Scaling

- **CPU**: 2-4 cores per 1000 concurrent players
- **Memory**: 4-8 GB for game state and connections
- **Network**: 1 Gbps for 5000+ concurrent players

### Horizontal Scaling

1. **Multi-Node Setup**
   ```bash
   # Node 1
   PORT=4000 NODE_NAME=node1@10.0.1.10 mix phx.server
   
   # Node 2
   PORT=4001 NODE_NAME=node2@10.0.1.11 mix phx.server
   ```

2. **Load Distribution**
   - Round-robin for matchmaking
   - Sticky sessions for active games
   - Geographic routing for latency

## Security Configuration

### SSL/TLS Setup

```elixir
config :massive_multiplayer_arena, MassiveMultiplayerArenaWeb.Endpoint,
  https: [
    port: 443,
    cipher_suite: :strong,
    keyfile: "priv/ssl/key.pem",
    certfile: "priv/ssl/cert.pem"
  ]
```

### Rate Limiting

```elixir
config :massive_multiplayer_arena,
  rate_limits: [
    input: {60, :per_second},
    chat: {5, :per_minute},
    spectator_join: {10, :per_minute}
  ]
```

## Troubleshooting

### Common Issues

1. **High Memory Usage**
   - Check for memory leaks in game processes
   - Monitor spectator connection count
   - Verify replay cleanup is working

2. **Poor Performance**
   - Profile game loop execution time
   - Check database query performance
   - Monitor network latency

3. **Connection Issues**
   - Verify WebSocket configuration
   - Check firewall settings
   - Test load balancer health checks

### Debug Commands

```bash
# Connect to running node
iex --name debug@127.0.0.1 --cookie your-cookie

# Check active games
MassiveMultiplayerArena.GameEngine.GameSupervisor.list_games()

# Monitor process memory
:observer.start()
```