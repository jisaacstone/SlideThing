---
name: slidething
description: Use ONLY when working with slide-deck generation projects using the Slidething platform. Use to create decks, generate slides, manage content/layout, and submit AI prompts via the HTTP API. Covers all Slidething REST endpoints and WebSocket channels.
---

# Slidething Platform API

Slidething is an AI-powered slide-deck generation platform. It exposes a REST API and WebSocket channels for creating decks, managing slides, generating content via LLM agents, and inspecting results.

Base URL: `http://localhost:4000`
WebSocket: `ws://localhost:4000/socket`

## REST API Endpoints

### Books

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/books` | List all books |
| POST | `/api/books` | Create a book. Body: `{"title": "...", "metadata": {...}}` (metadata optional) |
| GET | `/api/books/:book_id` | Get book details with pages |
| DELETE | `/api/books/:book_id` | Delete a book and all its pages/elements |
| POST | `/api/books/:book_id/pages` | Create a page in the book. Body: `{"title": "..."}` (title optional) |
| GET | `/api/books/:book_id/prompts?target_id=...` | List prompt history for a book |

### Pages

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id` | Get page with elements |
| DELETE | `/api/pages/:page_id` | Delete a page and all its elements |

### Elements

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id/elements` | List elements on a page |
| GET | `/api/elements/:element_id` | Get a specific element |
| PATCH | `/api/elements/:element_id` | Update element content/asset. Body: `{"content": "...", "asset_path": "..."}` |
| DELETE | `/api/elements/:element_id` | Delete an element |

### Layouts

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id/layouts` | List layouts for a page |
| GET | `/api/pages/:page_id/layouts/:format_id` | Get a specific layout |
| PATCH | `/api/pages/:page_id/layouts` | Move element in layout. Body: `{"format_id": "...", "element_id": "...", "x": 0.1, "y": 0.2}` — x/y are fractions of page (0..1) |

### Formats

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/formats` | List all available formats |
| GET | `/api/books/:book_id/formats` | List formats linked to a book |

### Agent Runs

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/runs` | Submit a prompt to the agent. Body: `{"prompt": "...", "book_id": "...", "target_type": "page\|element", "target_id": "..."}` (target_type/target_id optional) |
| GET | `/api/runs/:run_id` | Check run status. Returns: `{run_id, status, phase, prompt, book_id}` — `phase` is the currently running phase name (or null) |

### Assets

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/assets/*filename` | Serve a stored asset (image, etc.) |

## WebSocket Channels

Use the Phoenix JS client (`import { Socket } from "phoenix"`):

```javascript
const socket = new Socket("ws://localhost:4000/socket")
socket.connect()
```

### Run channel — `"run:{run_id}"`

Join to receive real-time progress from an agent run, or send a prompt to start one:

```javascript
const ch = socket.channel("run:run_abc123", {})
ch.on("run_event", (data) => console.log(data))
ch.on("agent_event", (data) => console.log(data))
ch.join()

// Start a run by sending a prompt (alternative to POST /api/runs)
ch.push("prompt", {prompt: "Create a 10-slide pitch deck about our product", book_id: "book_xyz"})
```

Outbound events (received):
- `run_event` — `{run_id, event, status, data, timestamp}` — orchestrator-level progress (`event` is e.g. `:started`, `:phase_started`, `:phase_completed`, `:completed`, `:failed`; phase name is inside `data`)
- `agent_event` — `{run_id, agent_type, scope, event, data, timestamp}` — per-agent progress (tool calls, LLM iterations)

Inbound messages (sent):
- `"prompt"` — `{prompt, book_id}` — Start an agent run directly from the socket

### Book channel — `"book:{book_id}"`

Request/reply channel for querying book state. No server-push events — all messages are synchronous replies.

```javascript
const ch = socket.channel("book:book_xyz", {})
ch.join()

// Query book state
ch.push("get_book", {}).receive("ok", (book) => console.log(book))
ch.push("get_page", {page_id: "page_123"}).receive("ok", (page) => console.log(page))
ch.push("get_element", {element_id: "elem_456"}).receive("ok", (el) => console.log(el))
ch.push("get_layout", {page_id: "page_123", format_id: "format-web"}).receive("ok", (l) => console.log(l))
```

Inbound messages (sent), all return a reply:
- `"get_book"` — Returns the book with its pages
- `"get_page"` — `{page_id}` — Returns page with elements and layouts
- `"get_pages"` — Returns all pages with elements and layouts
- `"get_element"` — `{element_id}` — Returns a specific element
- `"get_layout"` — `{page_id, format_id}` — Returns the latest layout for a page/format

## Run Status and Phases

Agent runs transition through states:

**Orchestrator statuses** (broadcast via WebSocket `run_event`):
- `idle` — run created, not yet started
- `planning` — agent is planning the generation strategy
- `executing` — agent is executing tool calls (content/image generation)
- `done` — run completed successfully
- `failed` — run failed with an error

**Agent-level statuses** (from `agent_event` messages):
- `idle` — waiting
- `thinking` — processing
- `executing_tools` — calling external tools
- `done` — finished
- `failed` — error

**GET /api/runs/:run_id response**:
```json
{
  "run_id": "run_abc123",
  "status": "done",
  "phase": "executing",
  "prompt": "Create a 5-page book about a penguin",
  "book_id": "book_xyz"
}
```

## Working with the API

### Creating a book

```bash
curl -X POST http://localhost:4000/api/books \
  -H "Content-Type: application/json" \
  -d '{"title": "My Book Title"}'
```

### Submitting an AI prompt

```bash
curl -X POST http://localhost:4000/api/runs \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create a 10-slide pitch deck about our product",
    "book_id": "book_abc123"
  }'
```

### Creating a page in a book

```bash
curl -X POST http://localhost:4000/api/books/book_abc123/pages \
  -H "Content-Type: application/json" \
  -d '{"title": "Page 1"}'
```

### Updating element content

```bash
curl -X PATCH http://localhost:4000/api/elements/elem_abc123 \
  -H "Content-Type: application/json" \
  -d '{"content": "Once upon a time...", "asset_path": "images/penguin.jpg"}'
```

### Updating element position in layout

```bash
curl -X PATCH http://localhost:4000/api/pages/page_abc123/layouts \
  -H "Content-Type: application/json" \
  -d '{"format_id": "format-web", "element_id": "elem_abc123", "x": 0.1, "y": 0.2}'
```

### Inspecting a book

```bash
curl http://localhost:4000/api/books/book_abc123
```

### Command-line quick start (mock provider, no keys)

```bash
cd /path/to/slidething
mix slidething.generate "Create a 5-page children's book about a penguin who wants to fly"
```

## Data Model

Content is a tree: `Book → Page → Element`

### Book
- `id` (string) — unique ID
- `title` (string) — book title
- `metadata` (map) — arbitrary metadata
- `created_at`, `updated_at` (timestamp)

### Page
- `id` (string)
- `book_id` (string) — parent book
- `position` (integer) — order within book
- `metadata` (map) — arbitrary metadata
- `created_at`, `updated_at` (timestamp)

### Element
- `id` (string)
- `page_id` (string) — parent page
- `element_type` (string) — e.g. "title", "text", "image", "caption"
- `position` (integer) — order within page
- `locked` (boolean) — whether this element is locked from editing
- `created_at`, `updated_at` (timestamp)

Elements store versioned content in **ElementVersion**:
- `id, element_id, version, run_id` — identifies the version
- `content` (string) — text content
- `asset_path` (string) — path to stored asset (image, etc.)
- `prompt` (string) — the prompt that generated this version
- `metadata` (map) — generation metadata

### Layout
Pages have layout versions per format in **LayoutVersion**:
- `id, page_id, format_id, version, run_id` — identifies the layout
- `element_layouts` (array of maps) — `[{element_id, x, y, width, height}, ...]` where all coordinates are fractions of page dimensions in 0..1

### Format
- `id, name` (string) — seeded formats: `"format-web"` (72 dpi) and `"format-print"` (300 dpi, 3 mm bleed)
- `unit` (string) — "cm" or "pt"
- `width, height` (number) — page dimensions in the given unit
- `dpi` (integer) — dots per inch for raster output
- `bleed_mm, safe_margin_mm` (number) — print safety margins

### Prompt
Tracks agent run requests:
- `id, book_id` (string)
- `user_prompt` (string) — the original user prompt
- `target_type` (string) — "page" or "element" (optional)
- `target_id` (string) — ID of target page/element (optional)
- `status` (string) — "running", "done", or "failed"
- `result_summary` (string) — final summary of what was generated
- `completed_at` (timestamp) — when the run finished
- `created_at` (timestamp)