---
name: slidething
description: Use ONLY when working with children's book creation projects using the Slidething platform. Use to create books, generate pages, manage content/layout, and submit AI prompts via the HTTP API. Covers all Slidething REST endpoints and WebSocket channels.
---

# Slidething Platform API

Slidething is an AI-powered children's book creation platform. It exposes a REST API and WebSocket channels for creating books, managing pages, generating content via LLM agents, and inspecting results.

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

### Layouts

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id/layouts` | List layouts for a page |
| GET | `/api/pages/:page_id/layouts/:format_id` | Get a specific layout |
| PATCH | `/api/pages/:page_id/layouts` | Update element position in layout. Body: `{"format_id": "...", "element_id": "...", "x": 10, "y": 20}` |

### Formats

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/formats` | List all available formats |
| GET | `/api/books/:book_id/formats` | List formats linked to a book |

### Agent Runs

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/runs` | Submit a prompt to the agent. Body: `{"prompt": "...", "book_id": "...", "target_type": "page\|element", "target_id": "..."}` (target_type/target_id optional) |
| GET | `/api/runs/:run_id` | Check run status. Returns: `{run_id, status, phase, prompt, book_id}` |

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
ch.push("prompt", {prompt: "Create a 5-page book about a penguin", book_id: "book_xyz"})
```

Outbound events (received):
- `run_event` — `{event, status, phase, data, run_id, timestamp}` — orchestrator-level progress
- `agent_event` — per-agent streaming progress (tool calls, LLM iterations)

Inbound messages (sent):
- `"prompt"` — `{prompt, book_id}` — Start an agent run directly from the socket

### Book channel — `"book:{book_id}"`

Join to receive page and book change notifications, or query book state:

```javascript
const ch = socket.channel("book:book_xyz", {})
ch.on("page_event", (event) => console.log(event))
ch.on("book_event", (event) => console.log(event))
ch.join()

// Query book state
ch.push("get_book", {})
ch.push("get_page", {page_id: "page_123"})
ch.push("get_element", {element_id: "elem_456"})
ch.push("get_layout", {page_id: "page_123", format_id: "fmt_789"})
```

Outbound events (received):
- `page_event` — page change notifications
- `book_event` — book change notifications

Inbound messages (sent):
- `"get_book"` — Fetch the book and all pages
- `"get_page"` — `{page_id}` — Fetch a specific page
- `"get_pages"` — Fetch all pages in the book
- `"get_element"` — `{element_id}` — Fetch a specific element
- `"get_layout"` — `{page_id, format_id}` — Fetch layout for a page/format

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
    "prompt": "Create a 5-page childrens book about a penguin",
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
  -d '{"format_id": "fmt_6x9", "element_id": "elem_abc123", "x": 50, "y": 100}'
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
Pages have layout versions per format that define bounding boxes in **LayoutVersion**:
- `id, page_id, format_id, version, run_id` — identifies the layout
- `element_layouts` (array of maps) — `[{element_id, x, y, width, height}, ...]` bounding boxes

### Format
- `id, name` (string) — e.g. "paperback 6x9"
- `unit` (string) — "mm" or "in"
- `width, height` (number) — page dimensions
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