# Agentic Flow Diagram

This document describes the plan-driven agentic execution system.

**Key design points:**
- The Planner LLM generates a structured JSON plan (no tool calls, no DB writes)
- The Orchestrator is pure Elixir code — not an LLM
- Book-level planning uses **semantic phase names** (decide_theme, generate_outline, …)
- Per-page work is a **self-contained pipeline**: one agent per page owns text + media + layout + validation and loops until satisfied
- Parallelism is implicit: book phases run serially, page phases run N-in-parallel

---

## Orchestrator State Machine

```
idle ──start_run──▶ planning ──plan received──▶ executing ──all phases done──▶ done
                      │                            │
                      │ plan invalid /             │ phase fails after
                      │ book create fails          │ max_retries
                      └───────▶ failed ◀───────────┘
```

At each event (planner task done, agent done, validator done), the orchestrator calls
`schedule_next_phases/1` → `PlanExecutor.find_ready_phases/4`:
- all `depends_on` phases complete?
- condition evaluates true (or nil)?
- not already running or done?

---

## Example Flow A — Create New Book

**Prompt:** "Create a 5-page children's book about a fox learning to share"

```
USER
 │
 ▼
Agent.API.start_run(prompt, book_id=nil)
 │  creates Prompt row (run_id), spawns Orchestrator via DynamicSupervisor
 │
 ▼
Orchestrator (status: :planning)
 │
 ▼
[Task.Supervisor] ──async_nolink──▶ Planner LLM (one call, no tools)
                                     │
                                     │ Returns JSON plan:
                                     │ {
                                     │   "book": {title, metadata},
                                     │   "pages": [{position, metadata} ×5],
                                     │   "phases": [
                                     │     decide_theme         (planner, book)
                                     │     generate_outline     (planner, book, deps: decide_theme)
                                     │     decide_pages         (planner, book, deps: generate_outline)
                                     │     decide_illustrations (planner, book, deps: decide_pages)
                                     │     assign_outline       (planner, book, deps: decide_illustrations)
                                     │     process_pages        (agent, page_pipeline, per_page,
                                     │                           deps: assign_outline)
                                     │     validate_book        (validator, book, deps: process_pages)
                                     │   ]
                                     │ }
                                     │
 ◀─── handle_info {ref, {:final_response, json}} ──────────────────────────────┘
 │
 │  PlanValidator.validate_plan!(phases)   ← cycles, bad refs, unknown conditions
 │  Book.create(title, metadata)           ← deterministic, no LLM
 │  Book.create_pages(book_id, 5 specs)   ← deterministic
 │  status: :executing
 │
 ▼
schedule_next_phases()
 │  find_ready_phases → [decide_theme]  (no deps)
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM: "decide_theme"
  Returns: {"theme": "kindness", "tone": "warm, gentle", "age": "4-7"}
  Stored as phase_context["decide_theme"]
 │
 ▼ (depends_on: ["decide_theme"] now satisfied)
[Task.Supervisor] ──▶ Planner LLM: "generate_outline"
  Context includes: decide_theme output
  Returns: {
    "beats": [
      "p1: fox alone in forest, feels lonely",
      "p2: fox meets rabbit who has extra berries",
      "p3: fox learns to offer help instead of taking",
      "p4: fox and rabbit share with the whole forest",
      "p5: fox feels happy surrounded by friends"
    ]
  }
  Stored as phase_context["generate_outline"]
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM: "decide_pages"
  Returns: {"page_count": 5, "spread_type": "single-page"}
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM: "decide_illustrations"
  Returns: {"illustration_pages": [1, 2, 3, 4, 5], "style": "watercolor"}
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM: "assign_outline"
  Context includes: all prior planner outputs + page_ids from DB
  Returns: {
    "pages": [
      {"page_id": "p1", "beat": "fox alone in forest", "has_image": true,
       "image_hint": "sad fox sitting under a tall oak tree"},
      {"page_id": "p2", "beat": "meets rabbit", "has_image": true, ...},
      ...
    ]
  }
  Stored as phase_context["assign_outline"]
 │
 ▼ (assign_outline done — process_pages is now ready)
schedule_next_phases() → [process_pages]
 │  scope: per_page → spawn one page_pipeline agent per page
 │
 ├──▶ Page Pipeline Agent (page_1)
 ├──▶ Page Pipeline Agent (page_2)
 ├──▶ Page Pipeline Agent (page_3)     ← all 5 run in parallel
 ├──▶ Page Pipeline Agent (page_4)
 └──▶ Page Pipeline Agent (page_5)

Each Page Pipeline Agent receives:
  - User prompt
  - Its page_id + assigned beat + image hint (extracted from assign_outline context)
  - All tools: create_element, update_element, generate_image, store_asset,
               propose_layout, get_format, get_page_elements, validate_page

Each agent runs its own loop (up to max_iterations):

  Page Pipeline Agent (page_1) loop:
    iter 1: create_element(type: title, content: "The Lonely Fox")
    iter 2: create_element(type: text, content: "Fox sat alone under the old oak…")
    iter 3: create_element(type: image, content: "sad fox under oak tree")
    iter 4: generate_image(prompt: "watercolor sad fox under oak, warm sunset tones")
            → asset_path: "images/p1-fox.png"
    iter 5: store_asset(element_id: img_elem, asset_path: "images/p1-fox.png")
    iter 6: propose_layout(page_id: p1, format_id: "format-web", element_layouts: [
              {element_id: title, x:0.1, y:0.05, w:0.8, h:0.1},
              {element_id: text,  x:0.1, y:0.17, w:0.8, h:0.25},
              {element_id: image, x:0.1, y:0.45, w:0.8, h:0.48}
            ])
    iter 7: validate_page(page_id: p1, format_id: "format-web")
            → {issue_count: 1, issues: [{rule: "bounds", element: image,
               message: "image bottom at 0.93, safe margin requires ≤ 0.90"}]}
    iter 8: propose_layout(…image height: 0.43 instead of 0.48…)
    iter 9: validate_page(page_id: p1, format_id: "format-web")
            → {issue_count: 0, issues: []}
    iter 10: final_response("page 1 complete")
    → sends {:agent_done, pid, "page 1 complete"} to Orchestrator

  (Other page agents run identical loops concurrently, each self-correcting)
 │
 │  All 5 {:agent_done} received → process_pages complete
 │
 ▼
schedule_next_phases() → [validate_book]
 │  step_type: :validator → runs inline (no LLM)
 │  Validator.Layout.validate(each_page, "format-web")
 │  Final sanity check across all pages
 │  Issues stored in state.validation_issues["validate_book"]
 │  (Page agents already self-corrected, so typically 0 issues here)
 │
 ▼
all_phases_complete? → true
complete_run()
Prompt.complete(run_id)
PubSub broadcast: {:run_event, :completed}
```

---

## Example Flow B — Add a Page to an Existing Book

**Prompt:** "Add a new page — the fox visits the market"
**Target:** `book_id = "book-abc123"` (5 pages already exist)

```
USER
 │
 ▼
Agent.API.start_run(prompt, book_id="book-abc123")
 │
 ▼
Orchestrator (status: :planning)
 │  book_id set → planner prompt includes existing book title, theme, page count
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM
  Returns JSON plan:
  {
    "book": null,          ← book already exists, don't recreate
    "pages": [
      {position: 6, metadata: {description: "fox at the market"}}
    ],
    "phases": [
      assign_page   (planner, book, depends_on: [])
      process_pages (agent, page_pipeline, per_page, depends_on: ["assign_page"])
    ]
  }
 │
 │  Book.create_pages(book_id, [{position: 6, ...}])  ← one new page
 │  page_ids = ["page-6-xyz"]   ← only the new page is in scope
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM: "assign_page"
  Context: existing book outline, new page description, page_id
  Returns: {"pages": [{"page_id": "page-6-xyz", "beat": "fox visits market",
                        "has_image": true, "image_hint": "busy market stalls"}]}
 │
 ▼
Page Pipeline Agent (page_6)
  Runs full loop: write text → generate image → layout → validate
  Self-corrects if validate_page returns issues
  → {:agent_done}
 │
 ▼
complete_run()  ← existing 5 pages untouched
```

---

## Example Flow C — Update Image on a Page

**Prompt:** "Regenerate the image on page 3 — make it more vibrant, sunset colors"
**Target:** `book_id = "book-abc123"`, `target_type = "page"`, `target_id = "page-3-id"`

```
USER
 │
 ▼
Agent.API.start_run(prompt, book_id, target_type="page", target_id="page-3-id")
 │
 ▼
Orchestrator (status: :planning)
 │  page-scoped → planner context includes current elements on page 3
 │
 ▼
[Task.Supervisor] ──▶ Planner LLM
  Returns JSON plan:
  {
    "book": null,
    "pages": null,         ← no new pages
    "phases": [
      update_image (agent, page_pipeline, per_page, depends_on: [])
    ]
  }
 │
 │  page_ids = ["page-3-id"]  ← filter_page_ids scopes to target only
 │
 ▼
Page Pipeline Agent (page_3)
  Instruction: "The user wants to regenerate the image with more vibrant, sunset colors.
                Existing image element: <id>, current asset: images/p3-fox.png.
                Generate a new image and store it. Then validate the page."

  iter 1: generate_image(prompt: "watercolor fox meeting rabbit, vibrant sunset palette,
                                   golden hour light through trees", aspect_ratio: "4:3")
          → asset_path: "images/p3-fox-v2.png"
  iter 2: store_asset(element_id: img_elem, asset_path: "images/p3-fox-v2.png")
  iter 3: validate_page(page_id: page-3-id, format_id: "format-web")
          → {issue_count: 0}
  iter 4: final_response("image updated")
 │
 ▼
complete_run()  ← only the image element on page 3 changed
```

---

## Page Pipeline Agent — Internal Loop Detail

The `page_pipeline` agent is the only per-page agent type. It owns the entire page lifecycle.

```
Page Pipeline Agent tools:
  get_page_elements   ← read current state of page
  create_element      ← add title / text / image elements
  update_element      ← revise existing content
  get_format          ← read page dimensions and safe margins
  propose_layout      ← set x/y/width/height for each element
  generate_image      ← call image provider
  store_asset         ← attach generated image to element
  validate_page       ← run Validator.Layout, returns issue list

Stopping conditions (agent decides):
  ✓ validate_page returns issue_count: 0  →  declare done
  ✓ Only minor warnings remain and agent judges acceptable  →  declare done
  ✗ max_iterations reached  →  {:agent_failed} → Orchestrator retries phase

The orchestrator never inspects per-page loop state.
It only sees: {:agent_done} or {:agent_failed}.
```

---

## Planner Context Flow

Each book-level planner phase stores its output in `phase_context`. Downstream phases receive relevant excerpts via `InstructionBuilder`.

```
phase_context map (in Orchestrator state):

  "decide_theme"         → %PlanContext{data: %{"theme" => "kindness", "tone" => "warm"}}
  "generate_outline"     → %PlanContext{data: %{"beats" => ["p1: ...", "p2: ...", ...]}}
  "decide_pages"         → %PlanContext{data: %{"page_count" => 5}}
  "decide_illustrations" → %PlanContext{data: %{"illustration_pages" => [1,2,3,4,5]}}
  "assign_outline"       → %PlanContext{data: %{"pages" => [
                               %{"page_id" => "p1", "beat" => "...", "has_image" => true},
                               ...
                             ]}}

InstructionBuilder (per-page scope):
  Dumps all upstream planner context into the instruction string.
  For assign_outline output, extracts only the entry matching this page_id:

    "=== Output from phase 'assign_outline' ===
     {page_id: p1, beat: 'fox alone in forest', has_image: true,
      image_hint: 'sad fox under oak tree'}"

  This way each page agent gets book-level context (theme, tone)
  AND its specific assignment (beat, image hint).
```

---

## Agent GenServer Lifecycle

```
Orchestrator: start_agent(run_id, :page_pipeline, {:page, page_id}, spec)
  DynamicSupervisor.start_child({AgentGenServer, opts})
    │
    ▼
AgentGenServer.init() → registers in AgentRegistry, status: :idle

Orchestrator: AgentGenServer.start_task(pid, instruction, context)
  cast {:start_task, instruction, context}
    │
    ▼
handle_cast {:start_task}
  messages = [system_prompt, user(instruction)]
  send(self(), :do_llm_call)
    │
    ▼
handle_info :do_llm_call  (repeats up to max_iterations)
  Task.Supervisor.async_nolink → LLM.Client.complete_json
    │
    ├─ {:tool_requests, calls}
    │    Tool.Registry.execute(tool, args)  ← for each call
    │    append [assistant(tool_calls), tool(tool_results)] to messages
    │    send(self(), :do_llm_call)
    │
    └─ {:final_response, text}
         send orchestrator: {:agent_done, self(), text}
         exit :normal

On max_iterations or error:
  send orchestrator: {:agent_failed, self(), reason}
  Orchestrator.handle_phase_failure → retry or fail_run
```

---

## Tool Registry

```
Tool.Registry.execute(tool_atom, args)
  │
  ├─ :get_page_elements  → Element.list(page_id)
  ├─ :create_element     → Element.create(page_id, type, content)
  ├─ :update_element     → Element.update(element_id, attrs)
  ├─ :get_format         → Book.get_format(format_id)
  ├─ :propose_layout     → Layout.propose(page_id, format_id, layouts)
  ├─ :generate_image     → Image.Client.generate(prompt, aspect_ratio)
  ├─ :store_asset        → Element.store_asset(element_id, asset_path)
  └─ :validate_page      → Validator.Layout.validate(page_id, format_id)
                           returns %{issue_count: N, issues: [...]}

Returns: %ToolResult{tool, success, data, error}
```

---

## Supervision Tree

```
Slidething.Application
  ├─ Slidething.Repo
  ├─ Slidething.Agent.Config      (loads agents.json)
  ├─ Slidething.RunRegistry       (Registry for Orchestrator lookup)
  ├─ Slidething.AgentRegistry     (Registry for Agent lookup)
  ├─ Slidething.PubSub
  ├─ Slidething.IOTaskSupervisor  (Task.Supervisor — planner LLM calls)
  ├─ Slidething.RunSupervisor     (DynamicSupervisor — one Orchestrator per run)
  │     └─ Orchestrator           (spawns page_pipeline agents via RunSupervisor)
  └─ SlidethingWeb.Endpoint

Crash behavior:
  Page agent crashes       → {:agent_failed} → Orchestrator retries or fail_run
  Planner Task crashes     → {:DOWN}         → fail_run immediately
  Orchestrator crashes     → DynamicSupervisor stops it, run stays in DB as failed
```

---

## PubSub Events

Topic: `"events:#{run_id}"`

```
{:run_event, %{run_id, event, status, data, timestamp}}

  :started            %{prompt, book_id}
  :planning_complete  %{book_id, page_count, phase_count}
  :phase_started      %{phase, step_type}
  :phase_completed    %{phase}
  :validation_issues  %{phase, issues: [...]}   ← from validate_book only
  :completed          %{duration_ms, pages}
  :failed             %{reason}
```
