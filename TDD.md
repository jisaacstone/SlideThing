
Table of Content

* API
* Internal Representation
* Agent Structure

# API

## Agentic API

These calls are routed through the agentic system (`Slidething.Agent.API`).

### start_run

The main interface. The Planner decides which phases to run based on the prompt and target.

* Prompt. Required. Describes the desired action (create book, edit page, restyle image, etc.)
* BookId. Optional. If omitted, a new book is created.
* TargetType. Optional. `"page"` or `"element"` — scopes the run to a specific item.
* TargetId. Optional. The page_id or element_id to target.

Returns `{:ok, run_id}`. Progress is streamed as events on the `"events:#{run_id}"` PubSub topic.

## Element API

These calls are deterministic. The are called by the agentic system, and also by the UI.

### Make Element

The programmatic interface. Like create, but deterministic. No agents.

* Element Id. Optional. If none is given a new element will be created.
* Page Id. Required.
* Element. The actual content. This is a polymorphic structure.
* Prompt. Optional. If this create call was a result of a prompt include it in metadata.

Element value (eg images) can be passed directly or as a file path, url.

### Update Metadata

* Id. Required. book-id, page-id or element-id
* Metadata. key-value pairs

### Retrieve

Query the tree structure
* Id. Required. book-id, page-id, element-id
* History. Optional. Include the N most recent versions
* Version. Optional. Retrieve a specific version

### Finalize

Create the final output.

* BookId. Required
* Format. Required

## Layout API

The CRUD calls for the layout, including bounding box, font, size, formatting, etc

This also includes calls to run our compile/validate steps

# Internal Representation

We separate content from layout.
Content is a tree structure.

    Book
      Page
        Element (Title)
        Element (Text)
      Page
        Element (Image)
        Element (Text)

Content structure, versions are stored in sqlite. Binary assets such as images are stored in the filesystem.

Every version of an image is given a UUID, which is used to lookup in the file store.

Versioning means slightly different things for different components.
A version of an Image is a UUID.
A version of a Text element is the text content.
A version of a Page is the elements and the layout.

Separating layout from elements allows us to target multiple layout formats.

All element types share a single `elements` table. Content and asset data live in `element_versions` (append-only).

Elements:
Id: UUID
PageId: UUID
ElementType: title | text | caption | image
Position: Int
Locked: Bool

ElementVersions:
Id: UUID
ElementId: UUID
Version: Int
RunId: UUID (the prompt that produced this version)
Content: String (text/title/caption)
AssetPath: String (image, filesystem path)
Prompt: String
Metadata: JSON

Layout happens at the page level. We reference the Format table.

Format:
Id: UUID
Name: String
Unit: cm | pt
Width: Float
Height: Float
DPI: Int
BleedMm: Float
SafeMarginMm: Float

Seeded formats: `format-web` (72 dpi, no bleed) and `format-print` (300 dpi, 3 mm bleed).

Layout:
FormatId: UUID
PageId: UUID
Version: Int
RunId: UUID
ElementLayouts: JSON array of
  ElementId: UUID
  X, Y, Width, Height: Float (fractions of page in 0..1)

Book:
Metadata:
  Theme
  Target
  Etc

Page:
BookId: UUID
Metadata:
  Description
  Prompt

# Agent Structure

The Orchestrator is pure code — no LLM. It drives a plan produced by the Planner pipeline, then executes phases in dependency order.

```
Orchestrator (pure code, GenServer)
  │
  ├── Planner pipeline (Task, 4 phases in sequence):
  │     decide → gather (tools) → condense → emit (submit_plan)
  │
  ├── Content phases (inline Task per element — returns raw text)
  │
  ├── Media phases (inline Task per image — calls Image.Client)
  │
  ├── Layout agents (AgentGenServer per page, parallel)
  │
  ├── Coordinator phase (inline Task — reviews coherence, may patch plan)
  │
  └── Validator phase (synchronous inline — deterministic layout checks)
```

**Planner** is a 4-step pipeline, not a single call. The gather step uses tools to read current book state before planning.

Planner gather tools: `get_outline`, `get_page_elements`, `get_element`, `get_recent_prompts`
Planner emit tool: `submit_plan`

**Content** writes text for a single element and returns it as plain text. No tools. The Orchestrator creates or updates the element directly.

**Media** generates an image for a page. The Orchestrator calls `Image.Client.generate/4` directly (no tools) and stores the result via `Element.create/update`.

**Layout** (AgentGenServer) takes element data and format dimensions — injected directly into the instruction — and calls `propose_layout` to record fractional (0..1) element positions.

Layout tools: `get_page_elements`, `get_format`, `get_element`, `propose_layout`
(In practice, element data is injected and the agent is told not to call get_page_elements/get_format.)

**Coordinator** is an optional review step that reads the full book content and can return `plan_patches` to adjust not-yet-started phases. Capped at 3 rounds.

**Validator** runs deterministic layout checks inline (no LLM). Issues are stored in orchestrator state. Conditional repair phases check this state before deciding to run.

**Research** handles book-level metadata decisions (theme, audience, style). Runs as a GenServer agent.

Research tools: `get_book`, `get_outline`, `update_book_metadata`, `update_page_metadata`

Layout and research phases parallelize automatically — one agent per page (or per scope) is spawned when the phase is ready. Content and media phases run as Tasks and also parallelize based on dependency ordering in the plan.

After every prompt, the orchestrator appends new element versions and layout versions for all affected pages.

# UI

The UI will be built on top of paged.js. A custom JS library will be built to allow the editing and movement of items on the page. We will also use paged.js to export to pdf, via headless browser. This allows high-fidelity between the UI and the final output.

The internal representation will be built on page load. A websocket will communicate changes between the client and server. Only diffs will be sent.

The user should be able to move things, edit text, and enter new prompts from the UI
