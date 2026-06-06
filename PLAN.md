# Implementation Status & Architecture

**Last Updated:** 2026-06-05
**Status:** MVP in progress — redesigning agentic flow to plan-driven execution

---

## Architecture Overview

### Technology Stack
- **Language/Runtime:** Elixir + OTP (BEAM)
- **Framework:** Phoenix (API + WebSocket, no LiveView)
- **Database:** SQLite via Ecto (with path to PostgreSQL)
- **Frontend:** Vue 3 + TypeScript + Vite
- **Page Rendering:** paged.js (browser-based, for preview + PDF)
- **LLM Integration:** OpenRouter, Google Gemini, Mock (pluggable via `config/agents.json`)

### Core Components

1. **Agentic System** (`lib/slidething/agent/`)
   - Orchestrator (GenServer) — pure code harness; executes structured plans
   - Agent GenServer (generic, reused per agent type/scope)
   - Five agent types: planner, content, layout, media, research
   - Tool Registry — central dispatch for all agent tool calls
   - Plan structs — Phase, GeneratedPlan, PlanContext, PlanValidator, PlanExecutor
   - Transcript persistence — all LLM calls logged to DB

2. **Deterministic Layer** (`lib/slidething/`)
   - Element API — CRUD on text/image/title/caption elements
   - Layout API — propose/validate element placement
   - Book API — create/manage books and pages
   - AssetStore — filesystem storage for images
   - Validators — deterministic layout checks; LLM content validator

3. **REST API + WebSocket** (`lib/slidething_web/`)
   - REST routes: /api/books, /api/pages, /api/elements, /api/layouts, /api/assets, /api/runs
   - Phoenix Channels:
     - `run:{run_id}` — agent progress, phase transitions
     - `book:{book_id}` — page/element/layout state sync (future)

4. **Web UI** (`assets/`)
   - Vue 3 SPA with TypeScript
   - Sidebar: book list, new book form
   - Main: page grid, element editor, prompt bar
   - paged.js integration for page rendering
   - Real-time updates via WebSocket

---

## Execution Flow (New: Plan-Driven)

```
User submits prompt via REST API or WebSocket
  ↓
Agent.API.start_run(book_id, prompt) creates Prompt row, starts Orchestrator
  ↓
Orchestrator calls Planner LLM (no tool calls — pure planning)
  └─ Planner outputs: GeneratedPlan JSON
       ├─ book: {title, metadata}
       ├─ pages: [{position, metadata}]
       └─ phases: [Phase...] (a DAG of named phases with deps + conditions)
  ↓
Orchestrator validates plan (DAG cycle check, dep refs)
  ↓
Orchestrator creates book + pages deterministically
  ↓
Orchestrator executes plan via PlanExecutor:
  loop:
    find_ready_phases(phases, completed_phases, conditions_state)
    → for each ready phase:
        :planner step  → call LLM, store output as PlanContext
        :agent step    → spawn N agents per scope (per_page → N, per_element → M)
        :validator step → run deterministic checks, store issues
    → when all ready phases complete:
        repeat loop
  ↓
When all phases complete (or conditional phases skipped):
  ↓
Commit versions to DB
Broadcast :completed via PubSub
DynamicSupervisor stops run tree
```

### Example Plan (Standard Book Creation)
```json
{
  "book": {"title": "...", "metadata": {...}},
  "pages": [{"position": 1, "metadata": {...}}, ...],
  "phases": [
    {"name": "generate_content", "step_type": "agent", "agent_type": "content",
     "scope": "per_page", "depends_on": []},
    {"name": "generate_layout", "step_type": "agent", "agent_type": "layout",
     "scope": "per_page", "depends_on": ["generate_content"]},
    {"name": "generate_media", "step_type": "agent", "agent_type": "media",
     "scope": "per_element", "depends_on": ["generate_layout"]},
    {"name": "validate_layout", "step_type": "validator", "agent_type": "validator",
     "scope": "per_page", "depends_on": ["generate_layout"]},
    {"name": "repair_layout", "step_type": "agent", "agent_type": "layout",
     "scope": "per_page", "depends_on": ["validate_layout"],
     "condition": "has_layout_issues", "max_retries": 2}
  ]
}
```

### Phase Rules
- **`depends_on: []`** — can start immediately
- **Phases with same satisfied deps** — run in parallel
- **`scope: :per_page`** — one agent per page, all in parallel
- **`scope: :per_element`** — one agent per image element, all in parallel
- **`scope: :book`** — one agent for whole book
- **`condition: "has_layout_issues"`** — only starts if condition evaluates true at runtime
- **`max_retries: 2`** — re-runs phase on failure up to N times

---

## Database Schema (Current)

| Table | Purpose |
|-------|---------|
| `books` | Book metadata (title, theme, target_audience) |
| `pages` | Ordered pages per book |
| `elements` | Text/image/title/caption elements, one per row |
| `element_versions` | Append-only history: content, asset_path, prompt, metadata |
| `layout_versions` | Per-page, per-format layout (bounding boxes, styling) |
| `formats` | Format definitions (width, height, DPI, margins, bleed) |
| `book_formats` | M:M join: books × formats (multi-format support) |
| `prompts` | User submissions (id = run_id), links to book_id |
| `agent_runs` | Per-agent invocation: orchestrator → agent_type → provider/model |
| `agent_messages` | Append-only LLM conversation: messages, tool_calls, tool_results |

**Versioning:** One user prompt = one committed version boundary per affected element/layout. Intermediate repair attempts stay in `agent_messages` only.

---

## Agent Configuration (config/agents.json)

```json
{
  "default_provider": "mock",
  "providers": {
    "mock": { "kind": "mock" },
    "openrouter": { "kind": "openrouter", "base_url": "...", "api_key_env": "OPENROUTER_API_KEY" },
    "gemini": { "kind": "gemini", "api_key_env": "GOOGLE_API_KEY" }
  },
  "agents": {
    "planner": {
      "provider": "mock",
      "model": "mock-model",
      "temperature": 0.2,
      "max_tokens": 4000,
      "max_iterations": 1,
      "system_prompt": "...",
      "tools": []
    },
    "content": { "tools": ["get_page_elements", "get_element", "create_element", "update_element"] },
    "layout": { "tools": ["get_page_elements", "get_format", "get_element", "propose_layout"] },
    "media": { "image_provider": "mock", "tools": ["get_element", "get_format", "generate_image", "store_asset"] },
    "research": { "tools": ["get_book", "get_outline", "update_book_metadata", "update_page_metadata"] }
  }
}
```

**Key change:** Planner has `"tools": []`. It outputs a JSON plan, not tool calls.

---

## Provider Abstraction

Two separate provider layers:

### LLM Providers (text generation)
- `Slidething.LLM.Provider` behaviour
- Implementations: Mock, Gemini, OpenRouter
- Callback: `complete_json(agent_spec, messages) → {:tool_requests, calls} | {:final_response, msg}`

### Image Providers (image generation)
- `Slidething.Image.Provider` behaviour
- Implementations: Mock, Gemini, OpenRouter
- Callback: `generate(provider, model, prompt, aspect_ratio) → {:ok, asset_path} | {:error, reason}`

---

## Plan Structs (lib/slidething/agent/plan.ex)

```elixir
defmodule Slidething.Agent.Phase do
  defstruct [:name, :step_type, :agent_type, :scope,
             :context, :condition, :depends_on, :max_retries, :config]
  # step_type: :planner | :agent | :validator
  # scope: :book | :per_page | :per_element
end

defmodule Slidething.Agent.GeneratedPlan do
  defstruct [:book_structure, :page_specs, :phases]
end

defmodule Slidething.Agent.PlanContext do
  defstruct [:phase_name, :scope, :data]
end
```

### PlanValidator checks
- No duplicate phase names
- All `depends_on` references exist
- No cycles (DFS)
- Valid `step_type`, `scope`, `condition` values

### PlanExecutor logic
- `find_ready_phases(phases, completed, conditions)` — returns phases whose deps are all in `completed` and whose condition (if any) evaluates true
- `evaluate_condition(:has_layout_issues, state)` — checks `state.validation_issues`

---

## Tool Registry (lib/slidething/tool/registry.ex)

Central dispatch: `Tool.Registry.execute(tool_atom, args) → %ToolResult{}`

**Agent tools:**
- Planner: *(none — planner has no tools)*
- Content: get_page_elements, get_element, create_element, update_element, delete_element
- Research: update_book_metadata, update_page_metadata
- Media: get_format, generate_image, store_asset
- Layout: get_page_elements, get_format, get_element, propose_layout

**Orchestrator-only (not callable by agents):**
- Book.create, Book.create_pages (orchestrator does this from plan)
- Validator.run_layout_checks, Validator.run_content_checks

---

## Supervision Tree

```
Slidething.Application
├── SlidethingWeb.Telemetry
├── Slidething.Repo
├── {Phoenix.PubSub, Slidething.PubSub}
├── {Registry, Slidething.AgentRegistry}        # {run_id, agent_type, scope} → pid
├── {Registry, Slidething.RunRegistry}          # run_id → orchestrator_pid
├── {DynamicSupervisor, Slidething.RunSupervisor}
├── {Task.Supervisor, Slidething.IOTaskSupervisor}
├── Slidething.Agent.Config                     # GenServer watching agents.json
└── SlidethingWeb.Endpoint

Per-run child tree (started by DynamicSupervisor):
Orchestrator GenServer
├── Agent GenServer(s)  (spawned per phase × scope, short-lived)
└── (Planner phase handled inline via Task.Supervisor, not GenServer)
```

---

## Implemented Features

✅ Core agent loop (LLM → tool calls → results → iteration)
✅ Provider abstraction (Mock, Gemini, OpenRouter)
✅ Async pattern (no blocking, all IO via Task.Supervisor)
✅ Tool Registry (central dispatch)
✅ Database schema (all tables created at startup)
✅ Prompt + Transcript persistence
✅ REST API (books, pages, elements, layouts, assets, runs)
✅ Phoenix Channels (run:* topics for progress)
✅ Image generation (with provider adapters)
✅ Web UI scaffolding (Vue 3 + Vite)
✅ Config system (agents.json with provider switching)

## In Progress

🚧 **Plan-driven orchestration** (this redesign)
   - Phase / GeneratedPlan / PlanContext structs
   - PlanValidator (DAG validation)
   - PlanExecutor (find_ready_phases, conditions)
   - Orchestrator rewrite (schedule_next_phases)
   - Planner prompt update (no tools, outputs JSON plan)
🚧 Validator phases (deterministic layout + LLM content)
🚧 Repair loops (conditional phases with max_retries)

## Future

🔲 Web UI layout editor (paged.js, drag-to-move)
🔲 Export (PDF, EPUB)
🔲 Book:{book_id} channel (element state sync)
🔲 Asset upload (UI)
🔲 Version history viewer
🔲 Multi-user support

---

## Running the System

### Setup
```bash
mix setup
export GOOGLE_API_KEY=...      # optional
export OPENROUTER_API_KEY=...  # optional
```

### Mock (free, no keys)
```bash
mix phx.server
cd assets && npm install && npm run dev

mix slidething.generate "Create a 5-page book about a penguin"
```

### Real LLM
```bash
SLIDETHING_AGENT_CONFIG=agents-openrouter.json mix phx.server
bin/generate-openrouter.sh "Create a book..."
```

---

## Key Module Map

| Module | Role |
|--------|------|
| `Slidething.Agent.Orchestrator` | Pure code harness: calls planner, executes plan phases |
| `Slidething.Agent.Plan` | Phase / GeneratedPlan / PlanContext / PlanValidator / PlanExecutor |
| `Slidething.Agent.InstructionBuilder` | Builds agent task instructions from phase + scope + context |
| `Slidething.Agent.GenServer` | Generic agent process (LLM loop, tool dispatch) |
| `Slidething.Agent.Config` | Loads/watches agents.json, runtime switching |
| `Slidething.Tool.Registry` | Central tool execution dispatch |
| `Slidething.LLM.Client` | Dispatches to provider by spec |
| `Slidething.LLM.Provider.{Mock,Gemini,OpenRouter}` | Provider implementations |
| `Slidething.Image.Client` | Image generation dispatch |
| `Slidething.Image.Provider.{Mock,Gemini,OpenRouter}` | Image provider implementations |
| `Slidething.Element` | Text element CRUD + versioning |
| `Slidething.Layout` | Layout version CRUD |
| `Slidething.Book` | Book/page CRUD |
| `Slidething.Prompt` | Prompt row CRUD (= run_id) |
| `Slidething.Transcript` | Agent run + message logging |
| `Slidething.AssetStore` | Filesystem image storage |
