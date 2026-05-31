Basic flow: [INPUTS] -> [INTERNAL REPRESENTATION] -> DECK

Internal representation:

DECK:
 DECK-METADATA
 SLIDES

SLIDES:
 SLIDE + SLIDES

SLIDE:
 SLIDE-METADATA
 COMPONENTS

COMPONENTS:
 COMPONENT + COMPONENTS

COMPONENT:
 COMPONENT-METADATA
 COMPONENT-VALUE

COMPONENT-VALUE
 TEXT
 IMAGE

---

The basic idea is that the internal representation can be generated or manually edited

There are three levels of work: DECK, SLIDE, COMPONENT.
At each level we have LOCKING and VERSIONING. LOCKING will preserve the value when re-generating the INTERNAL-REPRESENTATION from INPUTS.

INPUT -> REPRESENTATION flow can be run at any level. A full deck can be generated from an input. A single image can also be generated.

Examples:

I have a product spec (pdf) and some screenshots (png). I upload these to the interface, and write a prompt: "Generate a 3-4 slide presentation to present at the all hands to hype the new product launch".

The Inputs will become part of the deck metadata. The will also be passed to the internals to create the slides and components. The UI will show the generated slides.

I can then, for example, LOCK the first slide, and re-prompt: "The bullets should be shorter. Focus on user stories not technical implementation".

The first slide will remain the same, and the other slides will be re-generated. I can then decide actually I liked better the first image generated for the last slide. I can click on the generated image, and roll back to the previous version. I can also re-prompt for a single slide, or a single image.

So in this example we have some uploaded images. These will be default be included as-is. But I could add a prompt for a single image, eg "add a green roof to the building" and it would take the source image and the prompt, and generate a new image.

Technical Challenges:
Templating - most slides follow a simple template (Title only, Title and bullets, chart with short description, etc). Intelligently picking the correct template is important.
This can be rigid (model is given discreet choices) or dynamic (model is given some tooling and it can generate templates as-needed). We can also have some pre-defined user templates to create very rigid structure.

Which comes first: template or content? It makes most sense for the model first to generate a logical flow of content, and then the actual components, then the templates and slides, and finally run a formatting step.

Formatting: The model will need to intelligently decide if it should move things around, resize things, or edit the content. For text it could resize, change flow, reposition or change content. For Images it can resize, crop, reposition or regenerate. The agent will need to both identify problems and choose the correct solution. My experience is that agents are actually pretty bad at this. The UI should also allow for manual tweaking.

Theme/Palette - having metadata for an theme and/or palette will be desired - getting the model to actually follow has been a challenge for me in the past.

Questions:
Web editing of slides is probably a solved problem. Is there software existing we can build on top of?
What are the functional and other requirements?
Who are the target users? Initial launch, final market?
Size of screen - affects image resolution, text size?

---

## Example Workflows (OTP Process Model)

Process model: One Run GenServer per user prompt (started via DynamicSupervisor).
Agents (Orchestrator, Research, Content, Layout, Media) are stateless modules.
A shared Agent.Loop module runs the multi-turn LLM tool-call loop for any agent config.
Task.Supervisor handles parallel work within phases.

### Workflow 1: From-Scratch Book Build

Prompt: "Create a 10-page children's book about a fox who learns to share"

```
Run.start(book_id: nil, prompt)
  → DynamicSupervisor starts Run GenServer
  → status: :planning

Phase 1 — Research (sequential LLM loop):
  Agent.Loop.run(:research, context)
    → LLM requests tools: update_book_brief(theme, audience, outline)
    → Tool.Registry executes, returns result
    → LLM returns: final_response (book brief + page outline)

Phase 2 — Content (parallel per page):
  Task.Supervisor spawns 10 tasks:
    Each: Agent.Loop.run(:content, page_context)
      → LLM requests: create_element(text), create_element(title)
      → Returns: patch_proposal per page
  Run GenServer collects patches, applies via Element API

Phase 3 — Media (parallel, async):
  For pages needing images:
    Agent.Loop.run(:media, page_context)
      → generate_image (slow external call)
      → store_asset → returns patch
  Run GenServer collects, applies

Phase 4 — Layout (parallel per page, after content+media):
  Task.Supervisor spawns N tasks:
    Each: Agent.Loop.run(:layout, page_context_with_elements)
      → Returns: layout_changes patch
  Run GenServer collects, applies via Layout API

Phase 5 — Validate:
  Validator.Content + Validator.Layout
  If issues → :repairing → re-run relevant agents with issues (max 2-3)

Phase 6 — Commit versions, broadcast :completed, GenServer stops
```

Coordination: Run GenServer sequences phases (real dependencies between them).
Parallelism within phases via Task.Supervisor (pages are independent).
Subagents do NOT call sub-subagents. Orchestrator sequences everything.

### Workflow 2: Refining — Verbatim Text Update + Re-layout

Prompt: "Page 3 text should be: 'The fox sat alone under the old oak tree.'"

```
Run.start(book_id, prompt, target: {page_id, element_id})

Phase 1 — Orchestrator (1-2 LLM calls):
  Agent.Loop.run(:orchestrator, scoped_context)
    → Recognizes: verbatim text update, scoped to one page
    → Returns RunPlan: [content(page_id), layout(page_id)]

Phase 2 — Content (single page, short loop):
  Agent.Loop.run(:content, page_3_context)
    → update_text_element(element_id, verbatim text)
    → Returns patch

Phase 3 — Layout (single page):
  Agent.Loop.run(:layout, page_3_updated_context)
    → Text length changed → new bounding boxes
    → Returns layout patch

Phase 4 — Validate layout (skip content validation for verbatim user text)
Phase 5 — Commit, broadcast, stop
```

Orchestrator could be bypassed for simple intents (deterministic routing),
but kept for MVP to handle edge cases uniformly.

### Workflow 3: Re-rendering — User Provides Image + Prompt

Prompt: "Make this image more whimsical, watercolor style" + uploaded image

```
Run.start(book_id, prompt, target: {element_id})

Phase 1 — Orchestrator:
  Agent.Loop.run(:orchestrator, scoped_context)
    → Returns RunPlan: [media(element_id), layout(page_id)]

Phase 2 — Media (single element, slow):
  Agent.Loop.run(:media, element_context)
    → LLM refines prompt
    → generate_image (10-30s external call)
    → store_asset → new UUID
    → Returns patch with new asset UUID

Phase 3 — Layout (single page, after media):
  Agent.Loop.run(:layout, page_context_with_new_image)
    → Image dimensions may differ → new bounding box
    → Returns layout patch

Phase 4 — Validate layout (image DPI, bounds, overlap)
Phase 5 — Commit, broadcast, stop
```

Media is the slow step. Run GenServer blocks on the media Task.
For MVP this is acceptable. Async media with callback is a future optimization.

---

## Revised OTP Design (v2) — Stateful Agents, Async-First

### Principles

1. **Never block on IO.** All LLM calls, image generation, and HTTP go through
   `Task.Supervisor.async_nolink` + `handle_info`. No `Task.await` inside GenServers.
2. **Stateful agent GenServers.** Each agent instance is a GenServer holding
   conversation history, iteration count, and status. Registered via Registry.
3. **Separate planning process.** Planner is its own GenServer, distinct from
   the RunCoordinator that sequences execution.
4. **Clear agentic/deterministic boundary.** Agentic = LLM-driven GenServers.
   Deterministic = pure function modules. Tools bridge the two.

### Supervision Tree

```
Slidething.Application
├── Slidething.Repo
├── {Phoenix.PubSub, :slidething_pubsub}
├── {Registry, :unique, :agent_registry}      # {run_id, agent_type, scope} → pid
├── {Registry, :unique, :run_registry}        # run_id → pid
├── {DynamicSupervisor, :run_supervisor}      # Per-run supervision trees
├── {Task.Supervisor, :io_task_supervisor}    # All IO-bound work
├── Slidething.Agent.Config                   # GenServer: agents.json
└── SlidethingWeb.Endpoint

Per-run child tree (under :run_supervisor):

Run Supervisor (:one_for_all)
├── RunCoordinator     # GenServer — orchestrates phases, never blocks
├── Planner            # GenServer — agentic planning (started immediately)
├── ResearchAgent      # GenServer — dynamic, if plan requires
├── ContentAgent ×N    # GenServer — dynamic, one per page
├── LayoutAgent ×N     # GenServer — dynamic, one per page
├── MediaAgent ×N      # GenServer — dynamic, one per image task
└── ContentCritic      # GenServer — dynamic, validation phase
```

### Agent GenServer State

```elixir
%AgentState{
  agent_type: :planner | :research | :content | :layout | :media | :content_critic,
  run_id: String.t(),
  scope: String.t() | nil,           # page_id or element_id
  status: :idle | :thinking | :executing_tools | :done | :failed,
  agent_spec: AgentSpec.t(),
  messages: [Message.t()],           # LLM conversation history
  pending_task: Task.t() | nil,      # current async IO task ref
  iteration: integer(),
  max_iterations: integer(),
  result: term() | nil
}
```

### Async Pattern (all agent GenServers)

```elixir
def handle_info(:do_llm_call, state) do
  task = Task.Supervisor.async_nolink(:io_task_supervisor, fn ->
    LLM.Client.complete_json(state.agent_spec, state.messages)
  end)
  {:noreply, %{state | status: :thinking, pending_task: task}}
end

def handle_info({ref, result}, %{pending_task: %{ref: ref}} = state) do
  Process.demonitor(ref, [:flush])
  case result do
    {:tool_requests, calls} ->
      results = Enum.map(calls, &Tool.Registry.execute/1)
      new_messages = state.messages ++ [%Message{role: :tool, tool_results: results}]
      send(self(), :do_llm_call)   # next iteration, non-blocking
      {:noreply, %{state | messages: new_messages, status: :executing_tools}}

    {:patch_proposal, patch} ->
      send(state.coordinator_pid, {:agent_done, self(), patch})
      {:noreply, %{state | status: :done, result: patch}}

    {:final_response, msg} ->
      send(state.coordinator_pid, {:agent_done, self(), msg})
      {:noreply, %{state | status: :done, result: msg}}
  end
end

def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending_task: %{ref: ref}} = state) do
  {:noreply, %{state | status: :failed, pending_task: nil}}
end
```

### Message Protocol

```elixir
# Coordinator → Agent
{:start_task, task_description, context, coordinator_pid}
{:repair, [ValidationIssue.t()]}
:stop

# Agent → Coordinator
{:agent_done, agent_pid, result}
{:agent_failed, agent_pid, reason}
{:agent_progress, agent_pid, status}      # for UI updates

# Coordinator internal
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

| Agent | Tools (via Tool.Registry) |
|---|---|
| **Planner** | `get_book`, `get_outline`, `get_page_list`, `get_book_brief` |
| **Research** | `update_book_brief`, `update_page_metadata`, `get_book`, `get_outline`, `web_search` (optional) |
| **ContentAgent** | `get_page_elements`, `get_element`, `get_history`, `create_element`, `update_text_element`, `assign_element_to_page`, `update_element_metadata` |
| **MediaAgent** | `generate_image`, `store_asset`, `lookup_asset`, `inspect_image` |
| **LayoutAgent** | `get_layout`, `get_page_elements`, `get_format`, `propose_layout` |
| **ContentCritic** | `get_book_brief`, `get_page_elements`, `get_outline` (read-only) |

Deterministic-only operations (called by RunCoordinator, not by agents):
`commit_versions`, `validate_layout`, `apply_patch`

### RunCoordinator State Machine (Fully Async)

```
:idle → receive {:start, prompt, book_id} → start Planner → :planning
:planning → receive {:agent_done, planner, RunPlan} → start agents → :executing
:executing → receive {:agent_done, ...} from each agent
           → when phase complete: apply patches deterministically
           → start next phase agents
           → phases: research → content → media → layout
:validating → run Validator.Layout (deterministic)
            → start ContentCritic GenServer (agentic)
            → receive results
:repairing → send {:repair, issues} to relevant agents
           → receive new patches → re-validate (max 2-3)
:done → commit versions, broadcast :completed, supervisor stops tree
:failed → broadcast :failed, supervisor stops tree
```

Coordinator NEVER blocks. All transitions are message-driven.

### Communication Pattern (handle_cast vs handle_info)

**Coordinator → Agent:** Use `GenServer.cast` (async, no reply expected)
```elixir
GenServer.cast(agent_pid, {:start_task, task_desc, context})
```

**Task result → Agent:** Use `handle_info` (Task callbacks are regular messages)
```elixir
def handle_info({ref, result}, %{pending_task: %{ref: ref}} = state) do
  # process LLM result
end
```

**Agent → Coordinator:** Use `send` (plain message, Coordinator receives via `handle_info`)
```elixir
send(state.coordinator_pid, {:agent_done, self(), result})
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

### Communication Pattern (handle_cast vs handle_info)

**Coordinator → Agent:** Use `GenServer.cast` (async, no reply expected)
```elixir
GenServer.cast(agent_pid, {:start_task, task_desc, context})
```

**Task result → Agent:** Use `handle_info` (Task callbacks are regular messages)
```elixir
def handle_info({ref, result}, %{pending_task: %{ref: ref}} = state) do
  # process LLM result
end
```

**Agent → Coordinator:** Use `send` (plain message, Coordinator receives via `handle_info`)
```elixir
send(state.coordinator_pid, {:agent_done, self(), result})
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
