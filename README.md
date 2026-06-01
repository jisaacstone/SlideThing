# Slidething

AI-powered children's book creation platform (Elixir/Phoenix MVP).

## Setup

```bash
mix setup
```

Set API keys in your environment:

```bash
export GOOGLE_API_KEY=...      # for Gemini
export OPENROUTER_API_KEY=...  # for OpenRouter
```

Configure providers and models in `config/agents.json`. Default is `"mock"` which requires no API keys.

## Running

```bash
iex -S mix phx.server
```

The server starts at `http://localhost:4000`. Database tables are created automatically on startup.

## Quick start (mock, no API keys)

```bash
mix slidething.generate "Create a 5-page children's book about a penguin who wants to fly"
```

Streams agent progress in real time with icons (phases, tool calls, LLM iterations).

## With a real provider

```bash
# Gemini
GOOGLE_API_KEY=... mix slidething.generate "Create a children's book" --provider gemini

# OpenRouter
OPENROUTER_API_KEY=... mix slidething.generate "Create a children's book" --provider openrouter

# Or set once and run multiple times
export SLIDETHING_PROVIDER=openrouter
mix slidething.generate "Create a book about a fox"
mix slidething.generate "Refine page 3 layout"
```

## Switching providers at runtime (IEx)

```elixir
# Inspect current config
Slidething.Agent.Config.list_specs()

# Switch content agent to Gemini
Slidething.Agent.Config.set(:content, provider: "gemini", model: "gemini-2.5-flash")

# Run a generation
{:ok, run_id} = Slidething.Agent.API.start_run("Create a book...")

# Back to file defaults
Slidething.Agent.Config.reset()
```

## REST API

```bash
# Start the server
mix phx.server    # → http://localhost:4000

# Create a run
curl -X POST http://localhost:4000/api/runs \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Create a children's book about a fox"}'

# Check status
curl http://localhost:4000/api/runs/run_123456
```

## Phoenix Channels (browser UI)

```javascript
let socket = new Phoenix.Socket("/socket")
let channel = socket.channel("run:run_123")
channel.join()

channel.on("run_event", data => console.log(data))
channel.on("agent_event", data => console.log(data))

channel.push("prompt", {prompt: "Create a book..."})
  .receive("ok", resp => console.log("run_id:", resp.run_id))
```

Topic: `"run:{run_id}"`. Bidirectional — send prompts, receive streamed events.

## Media storage

Uploaded and generated images are stored under `~/.local/share/slidething/media/` (XDG standard). UUID filenames, no MIME filtering. Test env uses `/tmp/slidething_test_media`, wiped on startup.

```elixir
{:ok, path} = Slidething.AssetStore.store(image_bytes, "cover.png")
{:ok, data} = Slidething.AssetStore.retrieve(path)
```

## Testing

```bash
mix test
```

All tests use the mock provider — no API keys needed.

## Database

SQLite via Ecto. Tables created at startup (`lib/slidething/schema/bootstrap.ex`). No migrations.

## Architecture

```
UI/API prompt → Orchestrator → Planner → Content/Layout Agents
                                      → Validation
                                      → Commit versions
                                      → Websocket diff to UI
```

See `PLAN.md` for full design decisions.

## Export

```bash
env | grep API_KEY
```