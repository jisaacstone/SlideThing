# Slidething

AI-powered slide-deck generation platform (Elixir/Phoenix MVP).

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
mix slidething.generate "Create a 10-slide deck about AI-powered document generation"
```

Streams agent progress in real time with icons (phases, tool calls, LLM iterations).

## With a real provider

Provider/model config comes from `config/agents.json` (default: mock). Alternate configs available:

| Config file | Provider | Text models | Cost |
|---|---|---|---|
| `agents.json` | mock | mock-model | free, no keys |
| `agents-openrouter-free.json` | OpenRouter | llama-3.2-3b, gemma-4-31b | free tier |
| `agents-openrouter.json` | OpenRouter | gpt-4o-mini | ~$0.15/million tokens |

```bash
# Start dev server with OpenRouter cheap config
SLIDETHING_AGENT_CONFIG=agents-openrouter.json mix phx.server

# Or use the free-tier config
SLIDETHING_AGENT_CONFIG=agents-openrouter-free.json mix phx.server

# One-shot generation (free tier)
SLIDETHING_AGENT_CONFIG=agents-openrouter-free.json \
  mix slidething.generate "Create a 10-slide pitch deck for a SaaS product"
```

## Fast OpenRouter scripts

```bash
# Requires OPENROUTER_API_KEY in .env
bin/run-openrouter.sh                           # Dev server → agents-openrouter.json
bin/generate-openrouter.sh "Create a deck..."   # One-shot, agents-openrouter.json
```

## Switching providers at runtime (IEx)

```elixir
# Inspect current config
Slidething.Agent.Config.list_specs()

# Switch content agent to Gemini
Slidething.Agent.Config.set(:content, provider: "gemini", model: "gemini-2.5-flash")

# Switch all agents at once
for agent <- [:planner, :content, :research, :layout, :media] do
  Slidething.Agent.Config.set(agent, provider: "openrouter", model: "google/gemma-4-31b-it:free")
end

# Run a generation
{:ok, run_id} = Slidething.Agent.API.start_run("Create a deck...")

# Back to file defaults
Slidething.Agent.Config.reset()
```

Provider/model config lives in `config/agents.json`. No env-var overrides for provider/model — edit the file or use `Config.set/2` at runtime. API keys still come from env vars.

## REST API

```bash
# Start the server
mix phx.server    # → http://localhost:4000

# Create a run
curl -X POST http://localhost:4000/api/runs \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Create a 10-slide pitch deck about a new SaaS product"}'

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

channel.push("prompt", {prompt: "Create a deck..."})
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
UI/API prompt → Orchestrator → Planner pipeline (decide → gather → condense → emit)
                             → Content phases  (inline Tasks, one per element)
                             → Media phases    (inline Tasks, Image.Client)
                             → Layout phases   (AgentGenServer per page)
                             → Coordinator     (inline Task, may patch plan)
                             → Validator       (synchronous inline, per page)
                             → Repair layout   (if validation issues)
                             → Websocket events to UI
```

See `DESIGN.md` for full architecture decisions.

## Export

```bash
env | grep API_KEY
```