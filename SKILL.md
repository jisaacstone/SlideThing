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
| POST | `/api/books` | Create a book. Body: `{"title": "..."}` |
| GET | `/api/books/:book_id` | Get book details with pages |
| GET | `/api/books/:book_id/prompts?target_id=...` | List prompt history for a book |

### Pages

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id` | Get page with elements |

### Elements

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id/elements` | List elements on a page |
| GET | `/api/elements/:element_id` | Get a specific element |

### Layouts

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/pages/:page_id/layouts` | List layouts for a page |
| GET | `/api/pages/:page_id/layouts/:format_id` | Get a specific layout |

### Formats

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/formats` | List all available formats |
| GET | `/api/books/:book_id/formats` | List formats linked to a book |

### Agent Runs

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/runs` | Submit a prompt to the agent. Body: `{"prompt": "...", "book_id": "...", "target_type": "page|element", "target_id": "..."}` |
| GET | `/api/runs/:run_id` | Check run status |

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

Join to receive real-time progress from an agent run:

```javascript
const ch = socket.channel("run:run_abc123", {})
ch.on("run_event", (data) => console.log(data))
ch.on("agent_event", (data) => console.log(data))
ch.join()
```

Events:
- `run_event` — `{event, status, phase, data, run_id, timestamp}`
- `agent_event` — per-agent streaming progress (tool calls, LLM iterations)

### Book channel — `"book:{book_id}"`

Join to receive page and book change notifications:

```javascript
const ch = socket.channel("book:book_xyz", {})
ch.on("page_event", (event) => console.log(event))
ch.on("book_event", (event) => console.log(event))
ch.join()
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

Content is a tree: `Book → Page → Element (title | text | image | caption)`

Elements have content/asset versions. Pages have layout versions that define bounding boxes for elements within a format.