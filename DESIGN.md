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
1. **Planner** — 4-phase pipeline: decide → gather (with tools) → condense → emit. Produces a `GeneratedPlan`.
2. **Content** — Writes text elements per page (inline Task calls, not GenServers)
3. **Layout** — Places elements on page via GenServer agents (parallel per page)
4. **Media** — Generates images via `Image.Client` (inline Task calls, not GenServers)
5. **Coordinator** — Reviews coherence, may emit `plan_patches` to adjust remaining phases
6. **Validation** — Deterministic checks (synchronous, inline)

**Locking & Versioning:**
- Element versions are immutable (append-only)
- Layout versions are per-page, per-format (multi-format support)
- One user prompt = one committed version boundary per affected element/layout
- Intermediate repair attempts stay in transcript logs only

---

## Example Workflows (Plan-Driven Execution)

Process model: One Run Orchestrator GenServer per user prompt (started via DynamicSupervisor).
The Orchestrator is pure code — no LLM. It calls the Planner pipeline once to get a structured plan,
then executes the plan's phases in dependency order, spawning Agent GenServers for layout/research
phases or inline Task calls for content/media phases.

Agent configuration lives in `config/agents.json`.

### Workflow 1: From-Scratch Book Build

Prompt: "Create a 10-page children's book about a fox who learns to share"

```
Orchestrator.start_run(prompt)
  ↓
Step 1 — Planning (Orchestrator runs planner pipeline via Task.Supervisor):
  Phase A (decide): LLM decides if context gathering is needed → false for new books
  Phase B (gather): skipped (no book_id)
  Phase C (condense): skipped (nothing gathered)
  Phase D (emit): LLM calls submit_plan tool → returns GeneratedPlan JSON
    {book: {title, context}, phases: [...]}
  ↓
Step 2 — Orchestrator creates book (deterministic, no LLM):
  ensure_book(state) → book_id
  Pages are NOT pre-created; they are created lazily as phases reference page_index
  ↓
Step 3 — PlanValidator validates phases (cycle check, dep refs)
  ↓
Step 4 — PlanExecutor.find_ready_phases(phases, completed, running, state)
  → Returns phases with empty depends_on
  ↓
Phase "page_1_title" (step_type: :agent, agent_type: :content, scope: book):
  Inline Task: LLM call → returns text → Element.create(page_id, "title", text)
  page_id created lazily on first reference to page_index 0
  ↓
Phase "page_1_body" (depends_on: [page_1_title]):
  Inline Task: LLM call → returns text → Element.create(page_id, "text", text)
  ↓
Phase "page_1_image" (step_type: :agent, agent_type: :media, scope: book):
  Inline Task: Image.Client.generate(provider, model, prompt, aspect_ratio) → asset_path
  Derives subject from page's text elements
  ↓
...pages 2-10 execute with dependency ordering...
  ↓
Phase "generate_layout" (step_type: :agent, agent_type: :layout, scope: per_page):
  Spawn N LayoutAgent GenServers (one per page)
  Each receives elements and format data INJECTED into instruction (no tool calls needed)
  Each: calls propose_layout tool → sends {:agent_done} to Orchestrator
  ↓
Phase "validate_layout" (step_type: :validator, scope: per_page):
  Runs SYNCHRONOUSLY inline — Validator.Layout.validate per page
  Stores issues in state.validation_issues
  ↓
Phase "repair_layout" (condition: :has_layout_issues, max_retries: 2):
  Only runs if validation_issues is non-empty
  Spawn LayoutAgent GenServers with validation_issues context
  ↓
All phases done → complete_run → Broadcast :completed → Stop
```

### Workflow 2: Refining — Single Page Re-layout

Prompt: "Page 3 text should be: 'The fox sat alone under the old oak tree.'"

```
Orchestrator.start_run(prompt, book_id, "page", page_id)
  ↓
Planner pipeline (mode: :edit_page):
  Phase A (decide): book_id exists → runs decide call → needs_context=true
  Phase B (gather): calls get_outline, get_page_elements, get_recent_prompts
  Phase C (condense): condenses if > 3000 bytes
  Phase D (emit): calls submit_plan → scoped plan for target page only
  phases: [
    {name: "update_content", step_type: :agent, agent_type: :content, scope: :book,
     config: {op: "update", element_id: "<existing>", page_id: "<page_id>"}},
    {name: "generate_layout", step_type: :agent, agent_type: :layout, scope: :per_page,
     depends_on: ["update_content"]},
    {name: "validate_layout", step_type: :validator, scope: :per_page,
     depends_on: ["generate_layout"]}
  ]
  ↓
content → layout → validate → (repair if issues)
  ↓
complete_run → Broadcast → Stop
```

### Workflow 3: Image Restyle

Prompt: "Make this image more whimsical, watercolor style" + element_id

```
Orchestrator.start_run(prompt, book_id, "element", element_id)
  ↓
Planner pipeline (mode: :edit_element):
  Phase B (gather): calls get_element, get_recent_prompts (narrow tool set for element edits)
  Phase D (emit): calls submit_plan
  phases: [
    {name: "restyle_image", step_type: :agent, agent_type: :media, scope: :book,
     config: {op: "update", element_id: "<id>", page_id: "<page_id>", image_prompt: "..."}},
    {name: "generate_layout", step_type: :agent, agent_type: :layout, scope: :per_page,
     depends_on: ["restyle_image"]},
    {name: "validate_layout", step_type: :validator, depends_on: ["generate_layout"]}
  ]
  ↓
media → layout → validate → (repair if needed)
  ↓
complete_run → Broadcast → Stop
```

---

## OTP Architecture — Async-First Agent System

### Design Principles

1. **Never block on IO.** All LLM calls, image generation, HTTP via `Task.Supervisor.async_nolink` + `handle_info`.
2. **Stateful agent GenServers for layout/research.** Each is a GenServer holding LLM conversation history, iteration count, status.
3. **Inline Tasks for content/media.** Content and media phases run as plain `Task.Supervisor.async_nolink` calls — no GenServer wrapper.
4. **Orchestrator is pure code.** Calls Planner pipeline once, then executes the resulting plan. No LLM decision-making in the orchestrator itself.
5. **Plans are data.** A `GeneratedPlan` is a validated DAG of phases. Parallelization is implicit from scope + dependency rules.
6. **Clear agentic/deterministic split.** Agentic = LLM GenServers/Tasks. Deterministic = pure functions. Tools bridge them.
7. **Repair loops are first-class.** Validator phases store issues in state. Conditional repair phases re-run agents with error context (max_retries enforced).
8. **Coordinator phases can patch the plan.** A coordinator phase can return `plan_patches` to modify not-yet-started phases. Capped at `@max_coordinator_rounds = 3`.

### Supervision Tree (Actual Implementation)

```
Slidething.Application
├── SlidethingWeb.Telemetry
├── Slidething.Repo                                    # SQLite via Ecto
├── {Phoenix.PubSub, name: Slidething.PubSub}         # Event broadcast
├── {Registry, keys: :unique, Slidething.AgentRegistry}     # {run_id, phase_name, agent_type, scope} → agent_pid
├── {Registry, keys: :unique, Slidething.RunRegistry}       # run_id → orchestrator_pid
├── {DynamicSupervisor, name: Slidething.RunSupervisor, strategy: :one_for_one}
├── {Task.Supervisor, name: Slidething.IOTaskSupervisor}    # All async IO work
├── Slidething.Agent.Config                           # GenServer: watches agents.json
└── SlidethingWeb.Endpoint                            # Phoenix HTTP + WebSocket

Per-run processes (all children of Slidething.RunSupervisor, :one_for_one):

Orchestrator GenServer (via RunRegistry)
LayoutAgent GenServer(s)  # spawned per-page when layout phase executes
ResearchAgent GenServer(s) # spawned per scope when research phase executes
```

Note: Content and media phases run as plain Tasks under `Slidething.IOTaskSupervisor`, not as GenServer children.
The Orchestrator and all agent GenServers are siblings under `Slidething.RunSupervisor`.

**Registry lookups:**
- Agent by role: `{:via, Registry, {Slidething.AgentRegistry, {run_id, phase_name, agent_type, scope}}}`
- Orchestrator by run: `{:via, Registry, {Slidething.RunRegistry, run_id}}`

### Agent GenServer State

```elixir
%Slidething.Agent.GenServer{
  run_id: String.t(),
  agent_run_id: String.t() | nil,           # Links to agent_runs table
  agent_type: atom(),
  scope: nil | {:page, page_id} | {:element, element_id} | :book | ...,
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

### Orchestrator State

```elixir
%Slidething.Agent.Orchestrator{
  # Identity
  run_id: String.t(),
  prompt: String.t() | nil,
  book_id: String.t() | nil,
  target_type: String.t() | nil,           # "page" | "element" | nil
  target_id: String.t() | nil,
  # Status
  status: :idle | :planning | :executing | :done | :failed,
  started_at: DateTime.t(),
  completed_at: DateTime.t() | nil,
  # Plan execution
  generated_plan: GeneratedPlan.t() | nil,
  page_index_map: %{integer() => page_id}, # 0-based index → page_id, populated lazily
  # Phase tracking (MapSets of phase names)
  completed_phases: MapSet.t(),
  running_phases: MapSet.t(),
  # Pending work
  pending_agents: %{pid() => {phase_name, scope}},  # Layout/research GenServer pids
  pending_llm_tasks: %{ref() => task_tag},           # Content/media/planner/coordinator Task refs
  # Outputs
  phase_context: %{phase_name => PlanContext.t()},
  validation_issues: %{phase_name => [issue_map]},
  retry_counts: %{phase_name => integer()},
  coordinator_rounds: integer()                      # Guards against runaway patch loops
}
```

`pending_llm_tasks` tag format:
- `{:planner, phase_name}` — planner pipeline or mid-run planner step
- `{:coordinator, phase_name}` — coordinator phase
- `{:content, phase_name, page_id, op, element_type, element_id}` — content phase
- `{:media, phase_name, page_id, op, element_id, final_prompt}` — media phase

**Agent types in config/agents.json:**
- `planner` — Mid-run planner steps (has tools: get_book, get_outline, submit_plan)
- `planner_decide` — Decides if context gathering is needed (no tools)
- `planner_gather` — Gathers context via tools before planning
- `planner_summarize` — Condenses large gathered context
- `planner_emit` — Emits the execution plan via submit_plan tool
- `content` — Writes text elements (no tools; returns raw text)
- `layout` — Proposes element placement per page
- `media` — Config-only: specifies image_provider and image_model
- `coordinator` — Reviews coherence, may emit plan_patches (no tools)
- `research` — Book-level research and metadata updates

### Planner Pipeline (Initial Planning)

The initial plan is produced by a 4-phase sequential pipeline running inside a single `Task.Supervisor` task:

```
Phase A — Decide (planner_decide agent, no tools):
  Input:  static context (prompt + existing book state if any)
  Output: {needs_context: true|false}
  Skipped if book_id is nil (new book always skips gather)
  ↓
Phase B — Gather (planner_gather agent, with tools):
  Tools: get_outline, get_page_elements, get_element, get_recent_prompts
  (edit_element mode uses only get_element, get_recent_prompts)
  Output: plain-text summary of current content/structure
  Skipped if Phase A returned needs_context=false
  ↓
Phase C — Condense (planner_summarize agent, no tools):
  Only runs if gathered context exceeds 3000 bytes
  Compresses context to avoid token overload in emit phase
  ↓
Phase D — Emit (planner_emit agent, submit_plan tool):
  Input:  static context + condensed gathered context
  Output: GeneratedPlan via submit_plan tool call
  Retries once with a nudge if the model returns text instead of calling the tool
```

Planner modes determined by orchestrator state:
- `:create_book` — no book_id (new book)
- `:edit_book` — book_id present, no specific target
- `:edit_page` — target_type="page"
- `:edit_element` — target_type="element"

### Async Pattern in Agent GenServer (Actual)

**Step 1: Cast task from Orchestrator**
```elixir
def handle_cast({:start_task, task_description, context}, state) do
  system_message = %Message{role: :system, content: state.agent_spec.system_prompt}
  user_message = %Message{role: :user, content: task_description}
  agent_run_id = Slidething.Transcript.start_agent_run(state.run_id, state.agent_type, state.scope, state.agent_spec)
  
  new_state = %{state | agent_run_id: agent_run_id, messages: [system_message, user_message], status: :thinking}
  send(self(), :do_llm_call)
  {:noreply, new_state}
end
```

**Step 2: Spawn async LLM call**
```elixir
def handle_info(:do_llm_call, %{iteration: iter, max_iterations: max} = state) when iter >= max do
  fail_agent(state, :max_iterations_reached)
end

def handle_info(:do_llm_call, state) do
  task = Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
    Slidething.LLM.Client.complete_json(state.agent_spec, state.messages)
  end)
  new_state = %{state | status: :thinking, pending_task: task}
  broadcast_event(new_state, :llm_call_started, %{iteration: state.iteration + 1})
  {:noreply, new_state}
end
```

**Step 3: Handle LLM result (tool calls)**
```elixir
def handle_info({ref, {:tool_requests, calls}}, %{pending_task: %{ref: ref}} = state) do
  Process.demonitor(ref, [:flush])
  
  results = Enum.map(calls, fn %ToolCall{call_id: id, tool: t, args: a} ->
    %{Slidething.Tool.Registry.execute(t, a) | call_id: id}
  end)
  
  new_messages = state.messages ++ [%Message{role: :assistant, tool_calls: calls}] ++ 
                                   [%Message{role: :tool, tool_results: results}]
  Slidething.Transcript.append_messages(state.agent_run_id, state.iteration + 1, [assistant_msg, tool_msg])
  
  send(self(), :do_llm_call)
  {:noreply, %{state | messages: new_messages, status: :executing_tools, iteration: state.iteration + 1}}
end
```

**Step 4: Handle final response**
```elixir
def handle_info({ref, {:final_response, msg}}, %{pending_task: %{ref: ref}} = state) do
  Process.demonitor(ref, [:flush])
  Slidething.Transcript.complete_agent_run(state.agent_run_id, result)
  
  send(state.orchestrator_pid, {:agent_done, self(), {:final, msg}})
  {:noreply, %{state | status: :done, result: {:final, msg}}}
end
```

**No blocking.** `Task.await` never used in GenServers. Results flow via `handle_info`.

### Message Protocol

```elixir
# Orchestrator → Agent (layout/research GenServers)
GenServer.cast(pid, {:start_task, task_description, context})
:stop

# Agent → Orchestrator
{:agent_done, agent_pid, result}      # result is {:final, msg} or {:patch, patch}
{:agent_failed, agent_pid, reason}

# LLM Task → Orchestrator (content/media/planner/coordinator inline tasks)
{ref, {:final_response, json}}
{ref, {:ok, asset_path}}              # media tasks
{ref, {:error, reason}}
```

Note: `{:agent_progress, ...}` is NOT implemented.

### Agentic vs Deterministic Boundary

```
┌────────────────────────────────────────────────────┐
│                   AGENTIC                           │
│  LLM-driven, non-deterministic                      │
│                                                     │
│  Planner pipeline — decide/gather/condense/emit     │
│  ContentAgent     — writes text (inline Task)       │
│  MediaAgent       — drives image gen (inline Task)  │
│  LayoutAgent      — proposes element placement (GS) │
│  CoordinatorAgent — reviews coherence (inline Task) │
│  ResearchAgent    — book-level research (GS)        │
│                                                     │
│  These NEVER call deterministic APIs directly.       │
│  They request tool execution via Tool.Registry.     │
│  (Media is an exception: Image.Client called        │
│   directly by the Orchestrator task, not via tools) │
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
│  Image.Client   — delegates to image provider        │
│  Layout Validator — bounds, overflow, DPI, overlap   │
│  PlanValidator  — DAG cycle/ref checks               │
│  PlanPatcher    — applies coordinator patches        │
│  Renderer       — paged.js preview (future)          │
│  Exporter       — PDF/epub (future)                  │
└─────────────────────────────────────────────────────┘
```

### Tools by Agent

All tools execute via `Slidething.Tool.Registry.execute/2`. Agents never call external APIs or DB directly.
Media image generation is an exception — the Orchestrator calls `Image.Client.generate/4` directly in the
Task it spawns for media phases.

| Agent | Tools (from agents.json) |
|---|---|
| **planner** (mid-run steps) | `get_book`, `get_outline`, `submit_plan` |
| **planner_decide** | *(none)* |
| **planner_gather** | `get_outline`, `get_page_elements`, `get_element`, `get_recent_prompts` |
| **planner_summarize** | *(none)* |
| **planner_emit** | `submit_plan` |
| **Content** | *(none — returns raw text)* |
| **Layout** | `get_page_elements`, `get_format`, `get_element`, `propose_layout` (but element data is injected into the instruction to skip these) |
| **Media** | *(no tools — Orchestrator calls Image.Client directly)* |
| **Coordinator** | *(none — returns JSON with context + plan_patches)* |
| **Research** | `get_book`, `get_outline`, `update_book_metadata`, `update_page_metadata` |

**Deterministic-only (called by Orchestrator, not agents):**
`validate_layout` (inline sync call), `Image.Client.generate` (in media Task)

### Step Types

Valid `step_type` values for phases:

| step_type | How executed | Who handles result |
|---|---|---|
| `:planner` | `Task.Supervisor.async_nolink` → `run_planner_step_loop` | Orchestrator `handle_info {ref, {:final_response, ...}}` |
| `:agent` (content/media) | `Task.Supervisor.async_nolink` → inline LLM/image call | Orchestrator `handle_info {ref, result}` |
| `:agent` (layout/research) | `DynamicSupervisor.start_child` → `AgentGenServer` | Orchestrator `handle_info {:agent_done, pid, result}` |
| `:validator` | Synchronous inline call in Orchestrator | Returns immediately; no async |
| `:coordinator` | `Task.Supervisor.async_nolink` → single LLM call | Orchestrator `handle_info {ref, {:final_response, ...}}` |

### Coordinator Phases

Coordinator phases review in-progress book content for coherence and can modify the plan:

```
Phase "review_coherence" (step_type: :coordinator):
  Input: full book context (all pages, elements, phase_context)
  Output JSON: {
    "context": { assessment summary },
    "plan_patches": [
      {"op": "update", "name": "page_3_body", "max_retries": 2},
      ...
    ]
  }
  ↓
Orchestrator applies patches via PlanPatcher.apply/3:
  - Only patches not-yet-started phases (can't touch completed/running)
  - Only safe fields: max_retries, condition, config
  - Cannot add new coordinator phases
  - Capped at @max_coordinator_rounds = 3 total
  ↓
PlanValidator.validate_plan! on patched phases — rejected if invalid
```

### Orchestrator State Machine (Plan-Driven, Async)

```
:idle
  ↓ handle_call({:start_run, prompt, book_id, target_type, target_id})
:planning
  → Task.Supervisor spawns planner pipeline (decide → gather → condense → emit)
  ↓ handle_info({ref, {:final_response, plan_data}}) with {:planner, :initial_planning} tag
  → parse plan JSON → GeneratedPlan
  → PlanValidator.validate_plan!(phases)    # fail fast on bad plan
  → ensure_book(state)                     # create if new, reuse if existing
  → update book title from plan context
:executing
  → schedule_next_phases(state)
    → PlanExecutor.find_ready_phases(phases, completed, running, state)
    → for each ready phase:
        :planner    → Task.Supervisor async, store {:planner, phase_name} in pending_llm_tasks
        :coordinator → Task.Supervisor async, store {:coordinator, phase_name}
        :agent / content → Task.Supervisor async, store {:content, ...} tag
        :agent / media → Task.Supervisor async, store {:media, ...} tag
        :agent / layout|research → DynamicSupervisor start AgentGenServer, store pid in pending_agents
        :validator  → run synchronously inline, mark complete immediately
  ↓ handle_info({ref, {:final_response, ...}}) for LLM tasks
    → update element/layout/phase_context/plan as appropriate
    → mark phase complete, schedule_next_phases
  ↓ handle_info({:agent_done, pid, result}) for GenServer agents
    → remove pid from pending_agents
    → if all agents for phase done: mark phase complete, schedule_next_phases
  ↓ handle_info({:agent_failed, pid, reason})
    → if retry_count < max_retries: retry phase
    → else: transition to :failed
:done
  → Prompt.complete(run_id)
  → broadcast :completed via PubSub
:failed
  → Prompt.fail(run_id, reason)
  → broadcast :failed via PubSub
```

**Synchronous validator optimization:** After completing validator phases, `schedule_next_phases` is called recursively in the same message handler since validators complete synchronously and may immediately unblock the next phase.

### Page Creation (Lazy)

Pages are NOT pre-created from the plan. They are created on-demand when a phase first references a `page_index`:

```
resolve_and_register_page(phase, state):
  if config["page_id"] present → use it directly
  if config["page_index"] present:
    check page_index_map[idx]
    if nil → Book.create_pages(book_id, [%{position: idx+1}]) → register in page_index_map
    if found → reuse
  else → create at next available index (fallback)
```

`page_index_map` is a `%{integer → page_id}` map sorted by index. `scoped_page_ids/2` converts it to a sorted list for per-page phases.

### Communication Patterns (Actual)

**Orchestrator → Agent:** Via `GenServer.cast` (async, non-blocking)
```elixir
AgentGenServer.start_task(pid, task_description, context)
# which calls: GenServer.cast(pid, {:start_task, task_description, context})
```

**Task result → Orchestrator:** Via `handle_info` (Task ref result)
```elixir
def handle_info({ref, {:final_response, json}}, state) do
  case Map.pop(state.pending_llm_tasks, ref) do
    {{:content, phase_name, page_id, op, element_type, element_id}, pending} -> ...
    {{:coordinator, phase_name}, pending} -> ...
    ...
  end
end
```

**Agent → Orchestrator:** Via plain `send`
```elixir
send(state.orchestrator_pid, {:agent_done, self(), result})
send(state.orchestrator_pid, {:agent_failed, self(), reason})
```

**Broadcast to UI:** Via Phoenix.PubSub — ALL events use a single unified channel per run
```elixir
Phoenix.PubSub.broadcast(Slidething.PubSub, "events:#{run_id}",
  {:run_event, %{run_id:, event:, status:, data:, timestamp:}})

Phoenix.PubSub.broadcast(Slidething.PubSub, "events:#{run_id}",
  {:agent_event, %{run_id:, agent_type:, scope:, event:, data:, timestamp:}})
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

Content and media phases use scope `:book` with page targeting via `config["page_index"]` or `config["page_id"]`.
Layout phases use scope `:per_page` (Orchestrator fans out to one task per page).

### Monitoring and Observability

**Phoenix LiveDashboard** custom page for real-time agent monitoring:
- Running agents: type, scope, status, iteration count
- Conversation history: messages sent to LLM, responses
- Tool calls: which tools were requested, results
- Timing: how long each LLM call took
- Errors: failed tasks, retry attempts

Each agent GenServer broadcasts events via PubSub on `"events:#{run_id}"`:
```elixir
# Event types emitted by AgentGenServer:
:started, :task_started, :llm_call_started, :llm_response, :tools_executed, :completed, :failed

# Event types emitted by Orchestrator:
:started, :planning_complete, :phase_started, :phase_completed,
:validation_issues, :plan_patched, :completed, :failed
```

**Agent state inspection** for debugging:
```elixir
def handle_call(:get_state, _from, state) do
  {:reply, state, state}
end
```

### Streaming vs Non-Streaming LLM Calls

**Current:** Non-streaming (simpler, easier to parse JSON).

**Future:** Add streaming for better UX:
```elixir
Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
  LLM.Client.stream_json(agent_spec, messages, fn chunk ->
    send(agent_pid, {:llm_chunk, chunk})
  end)
end)
```

Monitoring dashboard shows progress (iteration count, tool calls) even without streaming.
