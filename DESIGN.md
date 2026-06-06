## Internal Representation

```
BOOK (root)
├── Book metadata (title, theme, target_audience, style)
├── Format associations (web, print, etc.)
└── PAGES (ordered)
    └── PAGE (position-indexed)
        ├── Page metadata (description, status)
        └── ELEMENTS (ordered)
            └── ELEMENT (text, title, image, caption)
                └── ELEMENT_VERSIONS (append-only)
                    ├── content (for text/title/caption)
                    ├── asset_path (for images)
                    ├── prompt (user intent)
                    └── metadata (style, content-type)

LAYOUT_VERSIONS (per page, per format)
├── Format geometry (width, height, DPI, margins, bleed)
├── Element layouts (bounding boxes + styling for each element)
└── Validation status
```

## Workflow Overview

**One user prompt** → creates one `prompts` row (becomes `run_id`) → starts Orchestrator GenServer → phases execute sequentially → commits versions → broadcasts websocket diffs.

**Phases:**
1. **Planner** — Parses user intent, creates book structure, decides page count
2. **Content** — Writes text, creates elements per page (parallel per page)
3. **Layout** — Places elements on page (parallel per page, per format)
4. **Media** — Generates/refines images (parallel per element, async)
5. **Validation** — Deterministic + LLM checks (future)

**Locking & Versioning:**
- Element versions are immutable (append-only)
- Layout versions are per-page, per-format (multi-format support)
- One user prompt = one committed version boundary per affected element/layout
- Intermediate repair attempts stay in transcript logs only

---

## Example Workflows (Plan-Driven Execution)

Process model: One Run Orchestrator GenServer per user prompt (started via DynamicSupervisor).
The Orchestrator is pure code — no LLM. It calls a Planner LLM once to get a structured plan,
then executes the plan's phases in dependency order, spawning Agent GenServers per scope.

Agent configuration lives in `config/agents.json`. Planner has no tools — it outputs JSON only.

### Workflow 1: From-Scratch Book Build

Prompt: "Create a 10-page children's book about a fox who learns to share"

```
Orchestrator.start_run(prompt)
  ↓
Step 1 — Planning (Orchestrator calls Planner LLM via Task.Supervisor):
  LLM input:  user prompt + optional existing context
  LLM output: GeneratedPlan JSON
    {book: {title, metadata}, pages: [...], phases: [...]}
  No tool calls. Pure text-to-plan.
  ↓
Step 2 — Orchestrator creates book + pages (deterministic, no LLM):
  Book.create(plan.book_structure) → book_id
  Book.create_pages(book_id, plan.page_specs) → [page_ids]
  ↓
Step 3 — PlanValidator validates phases (cycle check, dep refs)
  ↓
Step 4 — PlanExecutor.find_ready_phases(phases, completed={}, conditions={})
  → Returns phases with empty depends_on: ["generate_content"]
  ↓
Phase "generate_content" (scope: per_page, parallel):
  Spawn 10 ContentAgent GenServers (one per page)
  Each: LLM loop → create_element, update_element
  All send {:agent_done} to Orchestrator
  ↓
PlanExecutor.find_ready_phases → ["generate_layout"] (content done)
Phase "generate_layout" (scope: per_page, parallel):
  Spawn 10 LayoutAgent GenServers
  Each: LLM loop → propose_layout
  All send {:agent_done}
  ↓
PlanExecutor.find_ready_phases → ["generate_media", "validate_layout"] (both deps met)
Run in parallel:
  Phase "generate_media" (scope: per_element):
    Spawn MediaAgent GenServers per image element
    Each: generate_image (slow 10-30s) → store_asset
  Phase "validate_layout" (scope: per_page, validator):
    Run deterministic checks per page → collect issues
  ↓
PlanExecutor.find_ready_phases → ["repair_layout"] if has_layout_issues, else skip
Phase "repair_layout" (condition: has_layout_issues, max_retries: 2):
  Spawn LayoutAgent GenServers with validation_issues context
  Retry up to 2 times
  ↓
All phases done → Commit versions → Broadcast :completed → Stop
```

### Workflow 2: Refining — Single Page Re-layout

Prompt: "Page 3 text should be: 'The fox sat alone under the old oak tree.'"
(Scope: page_id + element_id already known)

```
Orchestrator.start_run(prompt, book_id, target: {:page, page_id})
  ↓
Planner LLM produces a scoped plan:
  phases: [
    {name: "update_content", agent_type: "content", scope: "per_page", depends_on: []},
    {name: "update_layout",  agent_type: "layout",  scope: "per_page", depends_on: ["update_content"]},
    {name: "validate_layout", step_type: "validator", scope: "per_page", depends_on: ["update_layout"]}
  ]
  pages: [{page_id: "<existing>"}]   ← only the target page
  ↓
Orchestrator skips book creation (book_id already exists)
  ↓
content → layout → validate → (repair if issues)
  ↓
Commit → Broadcast → Stop
```

### Workflow 3: Image Restyle

Prompt: "Make this image more whimsical, watercolor style" + element_id

```
Orchestrator.start_run(prompt, book_id, target: {:element, element_id})
  ↓
Planner produces plan:
  phases: [
    {name: "restyle_image", agent_type: "media",   scope: "per_element"},
    {name: "update_layout", agent_type: "layout",  scope: "per_page", depends_on: ["restyle_image"]},
    {name: "validate_layout", step_type: "validator", depends_on: ["update_layout"]}
  ]
  ↓
media → layout → validate → (repair if needed)
  ↓
Commit → Broadcast → Stop
```

---

## OTP Architecture — Async-First Agent System

### Design Principles

1. **Never block on IO.** All LLM calls, image generation, HTTP via `Task.Supervisor.async_nolink` + `handle_info`.
2. **Stateful agent GenServers.** Each agent is a GenServer holding LLM conversation history, iteration count, status.
3. **Orchestrator is pure code.** Calls Planner LLM once, then executes the resulting plan. No LLM decision-making in the orchestrator itself.
4. **Plans are data.** A `GeneratedPlan` is a validated DAG of phases. Parallelization is implicit from scope + dependency rules.
5. **Clear agentic/deterministic split.** Agentic = LLM GenServers. Deterministic = pure functions. Tools bridge them.
6. **Repair loops are first-class.** Validator phases store issues in state. Conditional repair phases re-run agents with error context (max_retries enforced).

### Supervision Tree (Actual Implementation)

```
Slidething.Application
├── SlidethingWeb.Telemetry
├── Slidething.Repo                                    # SQLite via Ecto
├── {Phoenix.PubSub, name: Slidething.PubSub}         # Event broadcast
├── {Registry, keys: :unique, Slidething.AgentRegistry}     # {run_id, agent_type, scope} → agent_pid
├── {Registry, keys: :unique, Slidething.RunRegistry}       # run_id → orchestrator_pid
├── {DynamicSupervisor, Slidething.RunSupervisor}     # Spawn per-run trees
├── {Task.Supervisor, Slidething.IOTaskSupervisor}    # All async IO work
├── Slidething.Agent.Config                           # GenServer: watches agents.json
└── SlidethingWeb.Endpoint                            # Phoenix HTTP + WebSocket

Per-run tree (supervised by Slidething.RunSupervisor, :one_for_all):

Orchestrator GenServer (via RunRegistry)
├── Planner GenServer         # LLM: parse intent, create book + pages
├── ContentAgent GenServer(s) # LLM: write text per page (spawned per page)
├── LayoutAgent GenServer(s)  # LLM: place elements per page (spawned per page)
└── MediaAgent GenServer(s)   # LLM: generate images (spawned per element, async)
```

**Registry lookups:**
- Agent by role: `{:via, Registry, {Slidething.AgentRegistry, {run_id, :planner, nil}}}`
- Orchestrator by run: `{:via, Registry, {Slidething.RunRegistry, run_id}}`

### Agent GenServer State

```elixir
%Slidething.Agent.GenServer{
  run_id: String.t(),
  agent_run_id: String.t() | nil,           # Links to agent_runs table
  agent_type: :planner | :content | :layout | :media,
  scope: nil | {:page, page_id},            # Page-scoped agents only
  orchestrator_pid: pid(),
  agent_spec: AgentSpec.t(),                # Config from agents.json
  status: :idle | :thinking | :executing_tools | :done | :failed,
  messages: [Message.t()],                  # LLM conversation history
  pending_task: Task.t() | nil,             # Async IO task ref (LLM call)
  iteration: integer(),
  max_iterations: integer(),
  result: term() | nil
}
```

**Agent types in config/agents.json:**
- `planner` — Parses user intent, creates book structure, decides layout
- `content` — Writes text elements per page
- `layout` — Proposes element placement per page per format
- `media` — Generates/refines images per element
- `research` — (Configured but not used in MVP execution path)

### Async Pattern in Agent GenServer (Actual)

**Step 1: Cast task from Orchestrator**
```elixir
def handle_cast({:start_task, task_description, context}, state) do
  system_message = %Message{role: :system, content: state.agent_spec.system_prompt}
  user_message = %Message{role: :user, content: task_description}
  agent_run_id = Slidething.Transcript.start_agent_run(state.run_id, state.agent_type, state.scope, state.agent_spec)
  
  new_state = %{state | agent_run_id: agent_run_id, messages: [system_message, user_message], status: :thinking}
  send(self(), :do_llm_call)  # Trigger LLM async
  {:noreply, new_state}
end
```

**Step 2: Spawn async LLM call**
```elixir
def handle_info(:do_llm_call, state) when state.iteration >= state.max_iterations do
  fail_agent(state, :max_iterations_reached)
end

def handle_info(:do_llm_call, state) do
  task = Task.Supervisor.async_nolink(:io_task_supervisor, fn ->
    LLM.Client.complete_json(state.agent_spec, state.messages)
  end)
  broadcast_event(state, :llm_call_started, %{iteration: state.iteration})
  {:noreply, %{state | status: :thinking, pending_task: task, iteration: state.iteration + 1}}
end
```

**Step 3: Handle LLM result (tool calls)**
```elixir
def handle_info({ref, {:tool_requests, calls}}, %{pending_task: %{ref: ref}} = state) do
  Process.demonitor(ref, [:flush])
  
  results = Enum.map(calls, fn call ->
    Slidething.Tool.Registry.execute(call.tool, call.args)
  end)
  
  # Append tool results and recurse
  new_messages = state.messages ++ [%Message{role: :assistant, tool_calls: calls}] ++ 
                                   [%Message{role: :tool, tool_results: results}]
  Slidething.Transcript.append_messages(state.agent_run_id, state.iteration, new_messages)
  
  send(self(), :do_llm_call)  # Next iteration
  {:noreply, %{state | messages: new_messages, status: :executing_tools}}
end
```

**Step 4: Handle final response**
```elixir
def handle_info({ref, {:final_response, msg}}, %{pending_task: %{ref: ref}} = state) do
  Process.demonitor(ref, [:flush])
  Slidething.Transcript.append_messages(state.agent_run_id, state.iteration, [%Message{role: :assistant, content: msg}])
  Slidething.Transcript.complete_agent_run(state.agent_run_id)
  
  send(state.orchestrator_pid, {:agent_done, self(), {:final, msg}})
  {:noreply, %{state | status: :done, result: msg}}
end
```

**No blocking.** `Task.await` never used in GenServers. Results flow via `handle_info`.

### Message Protocol

```elixir
# Orchestrator → Agent
{:start_task, task_description, context, orchestrator_pid}
{:repair, [ValidationIssue.t()]}
:stop

# Agent → Orchestrator
{:agent_done, agent_pid, result}
{:agent_failed, agent_pid, reason}
{:agent_progress, agent_pid, status}      # for UI updates

# Orchestrator internal
{:phase_complete, phase_name, results}
```

### Agentic vs Deterministic Boundary

```
┌────────────────────────────────────────────────────┐
│                   AGENTIC                           │
│  LLM-driven, non-deterministic, async GenServers    │
│                                                     │
│  Planner        — interprets intent → RunPlan       │
│  Research       — book brief, theme, outline        │
│  ContentAgent   — writes text, assigns elements     │
│  LayoutAgent    — proposes element placement        │
│  MediaAgent     — refines prompts, triggers gen     │
│  ContentCritic  — LLM rubric validation             │
│                                                     │
│  These NEVER call deterministic APIs directly.       │
│  They request tool execution via Tool.Registry.     │
└───────────────────────┬────────────────────────────┘
                        │ tool requests / results
                        │ (Tool.Registry dispatches)
┌───────────────────────▼────────────────────────────┐
│                 DETERMINISTIC                        │
│  Pure functions, no LLM, safe to call from Task     │
│                                                      │
│  Element API    — CRUD on content elements           │
│  Layout API     — CRUD on layout versions            │
│  Format API     — format queries                     │
│  Asset Store    — filesystem read/write              │
│  Version Control — snapshot, diff, rollback          │
│  Layout Validator — bounds, overflow, DPI, overlap   │
│  Patch Applier  — validate + apply agent patches     │
│  Renderer       — paged.js preview (future)          │
│  Exporter       — PDF/epub (future)                  │
└─────────────────────────────────────────────────────┘
```

### Tools by Agent

All tools execute via `Slidething.Tool.Registry.execute/2`. Agents never call external APIs or DB directly.

| Agent | Tools (from agents.json) |
|---|---|
| **Planner** | `create_book`, `create_pages`, `get_book`, `get_outline` |
| **Content** | `get_page_elements`, `get_element`, `create_element`, `update_element` |
| **Layout** | `get_page_elements`, `get_format`, `get_element`, `propose_layout` |
| **Media** | `get_element`, `get_format`, `generate_image`, `store_asset` |
| **Research** | `get_book`, `get_outline`, `update_book_metadata`, `update_page_metadata` |

**Deterministic-only (called by Orchestrator, not agents):**
`validate_layout`, `commit_versions`

### Orchestrator State Machine (Plan-Driven, Async)

```
:idle
  ↓ receive {:start_run, prompt, book_id, target_type, target_id}
:planning
  → Task.Supervisor spawns async Planner LLM call
  ↓ handle_info({ref, {:final_response, plan_json}})
  → parse plan JSON → GeneratedPlan
  → PlanValidator.validate_plan!(phases)    # fail fast on bad plan
  → Book.create + Book.create_pages         # deterministic, no LLM
  → store page_ids in state
:executing
  → schedule_next_phases(state)
    → PlanExecutor.find_ready_phases(phases, completed, conditions)
    → for each ready phase:
        :planner   → Task.Supervisor LLM call, store PlanContext on completion
        :agent     → spawn N Agent.GenServer per scope, GenServer.cast :start_task
        :validator → run deterministic checks inline (no GenServer), store issues
  ↓ handle_info({:agent_done, pid, result})
    → mark agent done in pending_agents
    → if all agents for phase done: mark phase done, schedule_next_phases
  ↓ handle_info({:agent_failed, pid, reason})
    → if retry_count < max_retries: retry phase
    → else: transition to :failed
:done
  → Prompt.complete(run_id)
  → broadcast :completed via PubSub
  → DynamicSupervisor stops run tree
:failed
  → Prompt.fail(run_id, reason)
  → broadcast :failed via PubSub
  → DynamicSupervisor stops run tree
```

**Key state fields added:**
```elixir
:generated_plan        # GeneratedPlan.t()
:page_ids              # [page_id] created from plan
:completed_phases      # MapSet of phase names that finished
:pending_agents        # %{pid => {phase_name, scope}}
:phase_context         # %{phase_name => PlanContext.t()} — outputs of planner steps
:validation_issues     # %{phase_name => [issue]} — outputs of validator steps
:retry_counts          # %{phase_name => integer}
```

**No blocking.** All transitions via message callbacks (`handle_info`). LLM calls async via Task.Supervisor.

### Communication Patterns (Actual)

**Orchestrator → Agent:** Via `GenServer.cast` (async, non-blocking)
```elixir
GenServer.cast(agent_pid, {:start_task, task_description, context})
```

**Task.Supervisor result → Agent:** Via `handle_info` (LLM call result)
```elixir
def handle_info({ref, {:tool_requests, calls}}, %{pending_task: %{ref: ref}} = state) do
  # Tool execution in Registry, send next LLM call
  send(self(), :do_llm_call)
end
```

**Agent → Orchestrator:** Via plain `send` (message, Orchestrator receives via `handle_info`)
```elixir
send(state.orchestrator_pid, {:agent_done, self(), result})
send(state.orchestrator_pid, {:agent_failed, self(), reason})
```

**Orchestrator internal:** Via `handle_info` for phase transitions
```elixir
def handle_info({:agent_done, agent_pid, result}, state) do
  new_state = collect_agent_result(state, agent_pid, result)
  if all_agents_done?(new_state) do
    new_state = process_phase_results(new_state)  # sequencing
  end
  {:noreply, new_state}
end
```

**Broadcast to UI:** Via Phoenix.PubSub
```elixir
Phoenix.PubSub.broadcast(Slidething.PubSub, "run_events:#{run_id}", 
  {:run_event, {:phase_completed, :content}})
```

### Agent Scope Flexibility

Agents are NOT restricted to per-page scope. The Planner decides scope based on task:

```elixir
scope: :book                          # whole book (outline, theme)
     | {:page, page_id}               # single page
     | {:pages, [page_id]}            # multiple pages
     | {:element, element_id}         # single element
     | {:elements, [element_id]}      # multiple elements
```

ContentAgent can work on book-level ("create outline"), page-level ("add content to page 3"), 
or element-level ("rewrite this paragraph"). The agent GenServer doesn't care about scope — 
it just works with whatever context it's given.

### Monitoring and Observability

**Phoenix LiveDashboard** custom page for real-time agent monitoring:
- Running agents: type, scope, status, iteration count
- Conversation history: messages sent to LLM, responses
- Tool calls: which tools were requested, results
- Timing: how long each LLM call took
- Errors: failed tasks, retry attempts

Each agent GenServer broadcasts events via PubSub:
```elixir
Phoenix.PubSub.broadcast(Slidething.PubSub, "agent_events:#{run_id}", 
  {:agent_event, self(), {:started, state.agent_type, state.scope}})
```

**Agent state inspection** for debugging:
```elixir
def handle_call(:get_state, _from, state) do
  {:reply, state, state}
end
```

### Streaming vs Non-Streaming LLM Calls

**MVP:** Start with non-streaming (simpler, easier to parse JSON).

**Future:** Add streaming for better UX:
```elixir
Task.Supervisor.async_nolink(:io_task_supervisor, fn ->
  LLM.Client.stream_json(agent_spec, messages, fn chunk ->
    send(agent_pid, {:llm_chunk, chunk})
  end)
end)
```

Monitoring dashboard shows progress (iteration count, tool calls) even without streaming.
