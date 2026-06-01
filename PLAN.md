# Agentic system architecture planning

**Session ID:** ses_181182c5effeNN8J0APB9UQOgF
**Created:** 5/31/2026, 9:39:42 AM
**Updated:** 5/31/2026, 9:56:14 AM

---

## User

read @AGENTS.md - We are making an implementation plan. The ideas for the architecture are around but not solidified. Let's iterate on design. The major components are (A) Agentic system (B) API Layer (C) UI. First let's focus on the Agentic system. We will need an orchistrator, and specific subagents. There will need to be validation and feedback in the subagents for both content and layout. The first questions are these: What agents and apis to use? How will the calls be made? How will credentials be stored? What language and framework to use? What db backend to use?

---

## Assistant (Plan · GPT-5.5 Pro · 3.3s)

---

## User

read @AGENTS.md - We are making an implementation plan. The ideas for the architecture are around but not solidified. Let's iterate on design. The major components are (A) Agentic system (B) API Layer (C) UI. First let's focus on the Agentic system. We will need an orchistrator, and specific subagents. There will need to be validation and feedback in the subagents for both content and layout. The first questions are these: What agents and apis to use? How will the calls be made? How will credentials be stored? What language and framework to use? What db backend to use?

We can have a simple config.json which has some agent -> model settings, and we can read api keys from the env (or use a .env?) but we will need some unified way of making calls. The openapi API definition is supported by all major model providers or no? since this is just a demp we can cheat and use openrouter maybe.

Language preference is a BEAM language such as erlang or elixir. But there may be advantage to use typescript for code sharing with UI, or using another language such as python to take advantage of an existing mature and stabel framework for agentic systems (if such a framework exists)

for a demo we can just use something like sqlite as our db backed.... probably

---

## Assistant (Plan · GPT-5.5 Pro · 54.9s)

_Thinking:_

**Planning design iteration**

I recognize that the user wants to iterate on a design while in read-only mode. They've already reviewed the AGENTS document. I should probably inspect both the PRD and TDD as part of this process. I plan to read these documents without making edits, perhaps beginning with listing the files to clarify what I’m working with. I’ll use the appropriate tools to access the PRD and TDD files and keep the user updated on my progress along the way.

I’ll ground the agentic-system design in the current PRD/TDD drafts first, then propose a concrete MVP architecture with tradeoffs and explicit decision points.

**Tool: read**

**Input:**
```json
{
  "filePath": "/home/larpy/projects/slidething/PRD.md",
  "offset": 1,
  "limit": 2000
}
```

**Output:**
```
<path>/home/larpy/projects/slidething/PRD.md</path>
<type>file</type>
<content>
1: # Purpose
2: 
3: Allow users to create a professional children's book.
4: 
5: # Goals
6: 
7: ## Professional Quality
8: 
9: Final output should be high quality - something that could be submitted to a publisher or self published.
10: 
11: ## Full Pipeline
12: 
13: Platform should adapt to changing needs as the book is developed.
14: From initial idea until final product. It should adapt and work well at all stages.
15: 
16: ## Rapid Iteration
17: 
18: Platform should allow the user to explore ideas and inspiration.
19: The user should not feel constrained by the platform.
20: The user should not feel that trying a new idea will slow down other progress.
21: 
22: # Requirements
23: 
24: ## Asset Management
25: 
26: Uploaded and generated assets (images, text) will need to be persisted.
27: 
28: ## User Interface
29: 
30: A UI should exist. All functionality should be discoverable.
31: 
32: ## API
33: 
34: An API should exist. The can be wrapped as a skill or MCP for integration with other agentic systems.
35: 
36: ## Import/Export
37: 
38: Common formats (pdf, epub, etc) should be supported. A user should be able to take an existing project, make some changes, and then export.
39: 
40: ## Versioning
41: 
42: The user should be able to rewind, get old versions of assets, and compare changes.

(End of file - total 42 lines)
</content>
```

**Tool: read**

**Input:**
```json
{
  "filePath": "/home/larpy/projects/slidething/TDD.md",
  "offset": 1,
  "limit": 2000
}
```

**Output:**
```
<path>/home/larpy/projects/slidething/TDD.md</path>
<type>file</type>
<content>
1: 
2: Table of Content
3: 
4: * API
5: * Internal Representation
6: * Agent Structure
7: 
8: # API
9: 
10: ## Agentic API
11: 
12: These calls are routed thought an agentic system
13: 
14: ### Create
15: 
16: The main interface. Inputs:
17: 
18: * Prompt. Required. The new prompt describing the desired user action
19: * Id. Optional. Constrain action to only deal with an explicit existing item in the internal representation.
20: Can be book-id, page-id, element-id
21: 
22: ### Refine
23: 
24: Specifically for formatting and validation. This will only update layout, not content.
25: 
26: * Prompt. Required. New layout-specific prompt
27: * Id. Optional. Book, page or element id. Multiple ids can be provided
28: 
29: ## Element API
30: 
31: These calls are deterministic. The are called by the agentic system, and also by the UI.
32: 
33: ### Make Element
34: 
35: The programmatic interface. Like create, but deterministic. No agents.
36: 
37: * Element Id. Optional. If none is given a new element will be created.
38: * Page Id. Required.
39: * Element. The actual content. This is a polymorphic structure.
40: * Prompt. Optional. If this create call was a result of a prompt include it in metadata.
41: 
42: Element value (eg images) can be passed directly or as a file path, url.
43: 
44: ### Update Metadata
45: 
46: * Id. Required. book-id, page-id or element-id
47: * Metadata. key-value pairs
48: 
49: ### Retrieve
50: 
51: Query the tree structure
52: * Id. Required. book-id, page-id, element-id
53: * History. Optional. Include the N most recent versions
54: * Version. Optional. Retrieve a specific version
55: 
56: ### Finalize
57: 
58: Create the final output.
59: 
60: * BookId. Required
61: * Format. Required
62: 
63: ## Layout API
64: 
65: The CRUD calls for the layout, including bounding box, font, size, formatting, etc
66: 
67: This also includes calls to run our compile/validate steps
68: 
69: # Internal Representation
70: 
71: We separate content from layout.
72: Content is a tree structure.
73: 
74:     Book
75:       Page
76:         Element (Title)
77:         Element (Text)
78:       Page
79:         Element (Image)
80:         Element (Text)
81: 
82: Content structure, versions are stored in sqlite. Binary assets such as images are stored in the filesystem.
83: 
84: Every version of an image is given a UUID, which is used to lookup in the file store.
85: 
86: Versioning means slightly different things for different components.
87: A version of an Image is a UUID.
88: A version of a Text element is the text content.
89: A version of a Page is the elements and the layout.
90: 
91: Separating layout from elements allows us to target multiple layout formats.
92: 
93: We will have two tables for elements
94: 
95: Media:
96: Id: UUID
97: Version: Int
98: Metadata:
99:   Prompt: String
100:   Content-Type: String
101: 
102: Text:
103: Id: UUID
104: Version: Int
105: Content: String
106: Metadata:
107:   Prompt: String
108:   Etc
109: 
110: Layout happens at the page level. We reference the Format table
111: 
112: Format:
113: Id: UUID
114: Unit: cm | pt
115: Width: Float
116: Height: Float
117: 
118: Layout:
119: FormatId: UUID
120: PageId: UUID
121: Version: Int
122: ElementLayouts:
123:   ElementId: UUID
124:   BoundingBox: (Point, Point)
125:   Etc
126: 
127: Book:
128: Metadata:
129:   Theme
130:   Target
131:   Etc
132: 
133: Page:
134: BookId: UUID
135: Metadata:
136:   Description
137:   Prompt
138: 
139: # Agent Structure
140: 
141: We have a tree of agents.
142: 
143: At the top level is the Orchestrator. It takes user input, calls subagents, and returns a response.
144: 
145: Below the Orchestrator are the Research, Content, Layout subagents.
146: 
147:            +------------------+
148:            |   Orchestrator   |
149:            +------------------+
150:              |       |       |
151:     +----------+-----------+----------+
152:     | Research |  Content  |  Layout  |
153:     +----------+-----------+----------+
154: 
155: The Research agent is our global planner. It makes project-wide decisions, searches the web, and is responsible for major theme and formatting decisions.
156: 
157: Required tools: Web Search, Book table CRUD operations, get-outline, get-content, preview
158: Required model capabilities: Reasoning
159: 
160: The Content agent is responsible for all content elements. The actual images and text. This agent also assigns these elements to specific pages.
161: 
162: Required tools: media-lookup, media-creation, get-page-elements, get-element, CRUD element operation
163: Media queries require image capable models - these can be a separate subagent.
164: 
165: The Layout agent takes the content and lays it out on the page.
166: 
167: Content and Layout agents work at the page level. So they can be run in parallel if multiple page edits are required by the orchestrator.
168: 
169: Content and Layout agents have a built in validation loop.
170: Content agent validates against the global requirements recorded by the Research agent.
171: Does this make sense, is it truthful, does it fit with the theme, is it in the correct order, etc
172: Layout validates with deterministic layout rules. Is the centering correct, does the text overflow, is it too small or too big, are the images of the correct resolution, etc.
173: 
174: After every prompt, the orchestrator agent creates a new version of all layouts and content.
175: 
176: # UI
177: 
178: The UI will be built on top of paged.js. A custom JS library will be built to allow the editing and movement of items on the page. We will also use paged.js to export to pdf, via headless browser. This allows high-fidelity between the UI and the final output.
179: 
180: The internal representation will be built on page load. A websocket will communicate changes between the client and server. Only diffs will be sent.
181: 
182: The user should be able to move things, edit text, and enter new prompts from the UI

(End of file - total 182 lines)
</content>
```

---

## Assistant (Plan · GPT-5.5 Pro · 275.0s)

_Thinking:_

**Considering framework choices**

The user prefers BEAM but is considering Python for a mature framework. I’m thinking, should I recommend Elixir for their MVP of a children’s book generator? So far, components include an agentic system, an API layer, and a UI. I want to suggest a frameworkless orchestrator using basic LLM calls and a tool registry for managing jobs. Elixir seems great for long-running processes, concurrency, and UI updates, but it’s important that the MVP doesn’t rely on a complex agent framework. I’ll need to explore the Elixir libraries more!**Evaluating tech options**

I’m considering using an OpenAI-compatible call to OpenRouter with JSON schema outputs and tool abstractions in Elixir. I’m thinking maybe a GenServer would work well for each run, using Oban jobs or a supervised Task for execution. SQLite could serve persistence needs, with Phoenix for both API and UI. However, there’s an alternative with Python's FastAPI and LangGraph for potentially faster agentic systems. Still, since BEAM is preferred, I need to recommend Elixir/Phoenix without the agent framework, focusing on OpenRouter for LLM calls and using GenServer for demo background jobs instead of Oban with SQLite.**Defining agent roles for MVP**

I need to clarify that Oban requires PostgreSQL, so I should recommend not using it unless PostgreSQL is chosen. For a demo with SQLite, we can use supervised Tasks and maintain persisted run records. SQLite's concurrency limitations are manageable for the MVP, especially with Ecto and ecto_sqlite3. 

I’m thinking of defining agent roles: an Orchestrator/Planner to interpret user input, a Research/Planning agent for high-level decisions, a Content agent for planning text and media, and a Layout agent for element placement. I might consider combining validators into loops within agents rather than having standalone LLM subagents. An optional media/image subagent could be included as needed.**Outlining validators and APIs**

I’m laying out the role of validators. The deterministic layout validator should always be a non-agentic function that checks for text overflow, bounds, margins, resolution, minimum font size, image aspect ratios, and collisions. For the content validator, I think an LLM rubric could work, potentially with the content agent initially performing a self-check. Later, separating it into a critic model could reduce bias. 

I also need to set up APIs, like an LLM provider abstraction for agent calls and a separate media generation process, while ensuring the tools exposed to agents are functional.**Defining orchestrator functionality**

The orchestrator is responsible for executing tool calls and logging the actions instead of the LLM hitting the database directly. It manages calls through an endpoint that receives prompts and creates "runs." The orchestrator loops through the process, asking the model for a summary of the current state and available tools, which then returns a structured plan for tool calls. 

I’m thinking about incorporating a system for persistence, where candidate changes are created in a draft transaction that gets validated before committing to the database. During the demo, we could commit after each tool call while including a run ID, and potentially allow rollback for invalid states. A deterministic API would help with managing transactions and version snapshots too!**Establishing credentials and framework recommendations**

I need to consider credentials carefully. For local development, I won't commit the `.env` file, as environment variables should be the source of truth. The config JSON will store provider URLs and model names, without any secrets. I need to load the `.env` file during development for API keys like `OPENROUTER_API_KEY` and `OPENAI_API_KEY`, while making sure that the SQLite database and asset store paths are also in the environment/config.

As for the language and framework, I’m leaning toward Elixir with Phoenix and Ecto/SQLite, paired with a direct HTTP client for LLM calls. This setup matches the BEAM preference and supports orchestration, concurrency, and websockets nicely. Sure, going with Elixir means fewer prebuilt agent components, but they could add unnecessary complexity and instability. I might consider Python for microservices if document rendering becomes crucial later, but it's not necessary for the MVP. An alternative could be Python FastAPI if speed and an agent framework take precedence.**Finalizing UI and database design**

I’m thinking that while UI code sharing might not be feasible, using WebSockets is certainly okay. For TypeScript options, the Vercel AI SDK could be good for code sharing with the UI, but for long-running workflows, I think I need to stick with Elixir and Phoenix unless the user prefers a Python agent framework. 

For the database, SQLite will work for the MVP, using Ecto for migrations, and storing assets in the filesystem. I’ll need to design tables for books, pages, layouts, and various versions. If multi-user collaboration happens later, I might consider transitioning to PostgreSQL. Also, I want to create a configuration for providers and agents to define capabilities clearly!**Defining schema and capabilities**

I want to establish a schema that links agents to their respective providers, models, capabilities, tool choices, temperature, and max tokens. It's crucial to include capabilities for tool calls and image generation. When the system starts up, I need to validate the configuration to ensure each selected model supports the necessary capabilities. 

I’m considering an OpenAPI definition for compatibility. Many providers expose Chat Completions, but image generation and tool execution might not be consistent across them. If using OpenRouter, I can access certain models through `/chat/completions`, though not all support tools or structured outputs. It’s essential to leverage capability flags in the config and avoid relying on provider-specific features.**Outlining call flows and orchestration**

Agents can ingest OpenAPI specifications, but not all providers can natively execute them. I need to clarify how calls will be made. The call flow starts with the user prompt, either through API `POST /agent/create` or a websocket prompt, followed by recording the run. The orchestration process involves several steps.

First, the current book and page state along with the project brief load. Then, the orchestrator generates a `RunPlan` JSON that details the intent, affected IDs, and subagent tasks. I execute subagent tasks in parallel or sequentially based on dependencies, ensuring each subagent receives only the pertinent context. They return a `PatchProposal` as typed JSON. The server applies the patch through a deterministic API, after which a validation loop checks content and layout, reporting any errors back with retries.

Finally, I commit versions atomically, log the run, and publish websocket diffs. I must remember to parallelize content for pages while validating layouts after content and handle image generation asynchronously due to its slower nature. Keeping the job or run state in mind will be crucial!**Identifying agents and API options**

I need to consider which agents and APIs we might use. For LLM text and reasoning, OpenRouter seems like a solid choice because it offers different model options. For instance, I could suggest using `anthropic/claude-3.5/3.7` as a strong reasoning model for the orchestrator and research tasks, while opting for a cheaper model for validators.

The user is interested in knowing what agents and APIs to utilize, so it's best to avoid hardcoding specific model names. Instead, I can emphasize that configurations should allow for flexibility. I could suggest using a strong model alongside a faster, cost-effective option. For OpenRouter, I might mention `openai/gpt-4o-mini`, but model availability can be uncertain. It's safer to present examples, like `anthropic/claude-sonnet-*` or `google/gemini-flash/pro`, without committing to specific names!**Considering implementation options**

For the implementation, I think the user should be able to set config values themselves. Regarding web search, I’m considering keeping it optional and off by default for the MVP. The research agent could use Tavily or the Brave API if necessary, but since the children’s book generation may not require web access, it’s safer to avoid it in the initial demo.

For images, since OpenRouter lacks standardization, it would be best to select a specific provider like OpenAI Images or Replicate/Stability, or even use placeholders for the demo. I’ll explore using the provider-specific API for the MVP while having abstractions in place for text and image generation. As for layout and rendering, I’ll utilize Paged.js with a headless Chromium for local previews rather than relying on an LLM API. The deterministic validator can measure using Paged.js too.**Outlining validation processes**

I need to describe the validation processes clearly. For content validation, I think I should conduct deterministic checks like ensuring proper length, page count, required IDs, style adherence, age range, and possibly reading level. Plus, I want an LLM to check for theme consistency, narrative order, and age appropriateness.

For layout validation, I’ll keep it deterministic for the MVP, focusing on bounds, overlap, minimum font sizes, image DPI, and safe areas. The layout agent can make necessary repairs. I might consider a visual critique using multimodal analysis after rendering, but that's optional and could be costly.

When it comes to orchestrator and subagents, I’m thinking minimalism is key. I’ll treat agents as roles with specific tools and response schemas instead of being fully autonomous. Each subagent will run as functions invoked by the orchestrator and have a designated system prompt, later configurable. In plan mode, no edits will be allowed, and I’ll implement max loops, timeouts, and audit logs to keep costs in check.**Planning MVP recommendations**

I should probably touch on "MCP/skill wrapping" later since the product requirement document (PRD) suggests the API could be MCP. I envision the deterministic APIs as the stable surface, with the agentic API exposed via HTTP for now and MCP functionality to follow. 

For the MVP Decision Proposal, I'm considering using Elixir with Phoenix for the API app. The agent framework would be a custom lightweight orchestrator, avoiding LangChain. For the LLM API, I’d opt for the OpenRouter's OpenAI-compatible chat for text agents, focusing on provider abstraction and JSON schema responses without testing additional provider tools just yet. For image handling, I think a provider-specific adapter using OpenAI Images or Replicate is a good starting point while storing results as assets in the filesystem, along with SQLite and Ecto for the database.**Confirming implementation details**

I should lay out the credentials, keeping them in the `.env` file for local development and maintaining a secretless config JSON. I definitely want to avoid using LangChain or CrewAI for the MVP. Also, I think it's best not to make every validator a standalone agent at first, and Postgres should be off the table unless we need durable jobs or multi-user support.

Before I dive into the implementation plan, I’d really like to ask the user a few clarifying questions to get their confirmation. Here are the four key points I want to cover: 

1. Are they comfortable choosing Elixir/Phoenix for the MVP backend, even though the agent frameworks might be less mature?
2. Are they okay with using OpenRouter for text LLM abstraction alongside a separate image provider adapter?
3. Should the MVP include web search functionality?
4. For the first demo, should it support actual image generation or just a placeholder/image-prompt workflow?
5. Would they prefer a single-user local demo or a multi-user setup? This will influence the credentials, database, and authentication design.**Considering OpenRouter and Database Choices**

I'm thinking about the pros and cons of using OpenRouter versus a direct provider for our demo. OpenRouter seems like a good fit, but there are risks, such as inconsistent tool support and concerns about data privacy and model availability. To mitigate this, I'll include adapter and config capabilities to use a direct provider later.

For the database, SQLite works great for a single-user demo, but if we're using BEAM for durable background jobs, I should suggest Postgres instead, since it has better library support. If we go with SQLite, I'll make sure not to promise a durable job queue and instead use simple process supervision.

I also want to point out that in development, the `.env` file will be loaded at boot by `dotenvy`, while in production, we'll use environment variables. I'll prepare a `.env.example` file with just the variable names, avoiding any secrets.

Finally, I think we need a table for `agent_runs` and `agent_messages/tool_calls` to ensure observability, replayability, and version tracking, which is especially important for our agentic system. And as for initial milestones, we should start with defining internal schemas and tool registries!**Planning LLM Client Implementation**

I’m thinking of how to implement the LLM client with OpenRouter and the config. Next steps involve creating an orchestrator run loop with some mock models and tools, then developing the content and layout agent along with schemas and validators. Remember, the user is focused on design, not implementation, so I'll keep my response concise and clear without mentioning my reading habits.

I'd like to frame "agents" in terms of architecture rather than just external APIs and propose an "operator runtime." I'll outline specifications for `AgentSpec`, `ToolSpec`, `RunContext`, and `Patch`, which will nicely fit all languages. Including a sample config JSON could be quite useful too.

Since I can't edit files in plan mode, I'll use code snippets in GFM format without nested bullets to keep it straightforward.**Discussing OpenAPI and Tool Compatibility**

I’m considering how to phrase the support for OpenAPI definitions across major model providers. To clarify: if the user means OpenAI-compatible APIs, then yes, it’s broadly supported, but not uniformly. However, OpenAPI schemas aren’t universally accepted in agent or tool runtimes.

OpenRouter does offer a unified `chat/completions`, but capabilities vary by model, which can be described in a capability matrix. For structured outputs, we can use guidelines from OpenAI as well as OpenRouter, but not all models support this uniformly. 

For MVP purposes, it seems best to stick with OpenAI-style `tools` when the model indicates support, especially since many major models allow tool calling through OpenRouter.**Analyzing Tool Call Approaches**

Uniformity in API support is a challenge, but I think we can make both approaches work. My preferred method would be to use OpenAI-compatible chat completions with tools, but only for models that declare `tool_calls: true`. As a fallback, we could implement a structured JSON response schema for "actions" that we parse locally. 

If we're starting from scratch, perhaps a simpler JSON schema response might be the way to go. Yet, agents still require tools to operate effectively. The model can suggest actions in JSON format for the runtime to execute deterministic tools, avoiding provider-specific tool_calls. 

For example, the JSON could look something like this:
```
{ "thought_summary": "...", "actions": [{ "tool": "get_page", "args": {...}}], "done": false }
```

This method is essentially manual tool calling, which is more portable. Although OpenAI-compatible tools offer convenience, I need to weigh the benefits. Tool-call APIs can vary, but OpenRouter supports them. While manual structured JSON may use more tokens, it gives us better control and consistency across providers. Ultimately, a unified approach for making calls is essential.**Implementing the JSON Structure**

If I’m using OpenRouter with a config, I should implement `LLM.complete_json(agent, messages, schema)` to avoid relying on provider tool calls. The agent should then output one of the fixed union types, like `request_tools` with a list of tool calls, `propose_patch`, or `final_response`. This structure is robust. 

However, I notice that structured output JSON schemas aren't universally supported. I can recommend using a "structured JSON action loop" with schema validation for the MVP and then switch to provider-native tool calling later for optimization. 

It's crucial to keep in mind that agents should never call APIs directly; all calls must go through the backend. For validation, I think we can use a `ContentValidator` LLM that acts as a critic, leveraging the same model with a different prompt or even a more cost-effective model for efficiency. Additionally, layout validation should always be deterministic, and I could potentially include a visual validator with a multimodal model after rendering a screenshot, although that might not be the first step. 

I should consider specific subagents like:
1. Orchestrator
2. Book/Research Planner
3. Page Content Agent
4. ...**Organizing Agent Roles**

I'm thinking about structuring my agent roles for the project. So far, I have ideas for:

1. Orchestrator
2. Research Agent
3. Content Agent
4. Media Agent
5. Layout Agent
6. Content Critic/Validator
7. Possibly a Layout Repair function, but that might overlap with the Layout Agent for the MVP.

It might be helpful to create an "agents" table to clarify their purposes and how they interact. This table can include columns like Agent, Purpose, Tools/APIs, Model Capability, and when each agent runs. This way, I have a clear overview of the roles and responsibilities of each agent in the system!**Designing Agent Table**

I'm thinking of creating a table with six agents, structured like this:

1. **Orchestrator**: Handles strong reasoning and spawns subagents, but no write tools. Uses LLM chat for deterministic retrieval and state management.
2. **Research/Book Brief**: Focuses on project goals and outlines, with optional web search tools for book metadata management.
3. **Content Writer**: Responsible for creating and editing text and image prompts, using various tools for content management and validation.
4. **Media Agent**: Refines image prompts, generates images, and ensures asset quality with necessary APIs.
5. **Layout Agent**: Manages layout JSON, validating and rendering previews with specific layout tools.
6. **Content Validator/Critic**: Performs deterministic checks without writing capabilities, using an LLM rubric.

There's also a need for APIs: 

- **External**: For LLM text/reasoning (OpenRouter), image processing, and optional web search.
- **Internal**: The Agentic API for managing agents and tools without making internal HTTP calls. 

This layout should provide a clear framework for each agent’s purpose and capabilities!**Creating Call Diagram**

I need to outline a call diagram that shows how the components connect:

```
UI -> API -> Orchestrator.run
           -> LLM.complete_json(:orchestrator)
           -> Research/Content/Layout agent modules
           -> ToolRegistry -> Ecto/FS/Paged preview/Image API
           -> Validators -> commit versions -> websocket diff
```

No nested bullets here. Now, I should also discuss the idea of "API wrapping as skill/MCP". It’s essential to design internal tools around JSON schemas while ensuring that both HTTP OpenAPI and MCP can be generated or wrapped later. 

I want to define the tool schemas now, steering clear of provider-specific details. It’s worth mentioning the difference between OpenAPI support and OpenAI, focusing on compatible JSON Schema definitions. 

In terms of security and storage, I should handle secrets in the environment and avoid putting API keys directly in the database or config. Also, for the DB logs, we might consider redacting prompts while ensuring generated content and prompt logs aren't secretive. Lastly, using SQLite in WAL mode could be beneficial for our DB backend.**Configuring Elixir Ecto and Frameworks**

I’m considering configuring Ecto with `journal_mode: :wal` for efficient handling. I know not to put images into SQLite and instead use asset files stored on disk. If I need a migration path to Postgres for a multi-user setup, it’s best to mention Postgres and Oban for robust background jobs.

Regarding the Elixir framework, I might opt for Phoenix without LiveView initially, using APIs and static UI/JS with websocket channels. Since the UI employs paged.js, I think Phoenix Channels will be sufficient. 

For other aspects, I’ll use Ecto for SQLite, Req for HTTP, Jason, Finch, and possibly Bandit or Cowboy for networking, along with validation libraries like ex_json_schema or NimbleOptions. 

Using a `Task.Supervisor.async_stream_nolink` for page agents is smart as it maintains a persistent run state in the database, ensuring changes are versioned even if a process dies. Also, if the UI is separate, Phoenix could handle JSON/websockets while using Vite for the UI.

Lastly, I might look into Python frameworks, where LangGraph seems like a mature and stable option among agentic systems.**Evaluating Agent Framework Choices**

I'm considering PydanticAI as a modern choice, but I realize that agent frameworks aren't inherently magic. Custom validators, tool schemas, and state management still need to be built. For an MVP, a direct runtime approach might be simpler.

If the main priority is experimentation, I could use Python; however, if architecture and concurrency are crucial, Elixir might be the better option. Regarding TypeScript, the value of code sharing sounds appealing, but since the contract is JSON, we can generate TypeScript types from JSON or OpenAPI later. I don’t want to make TypeScript the sole reason for choosing it.

If I consider LangGraph later, it could run as a worker service with a shared tool API. I might draft a decision matrix outlining pros and cons for clarity while keeping the final verbosity concise.**Final Recommendations for Implementation**

I need to emphasize that no major decisions should be made without explicit confirmation. My recommendation is to wait for confirmation before moving forward. 

I might consider asking a short question at the end and proposing a list of decisions to confirm, presented with checkboxes:
1. Use Elixir/Phoenix as the backend and agent runtime.
2. Use SQLite plus the filesystem for storage.
3. Use OpenRouter for text LLM via OpenAI-compatible `/chat/completions`.
4. Choose a provider-specific image adapter and select the image API later.
5. Implement a manual JSON action loop instead of a heavy agent framework.

This way, the user can respond with a yes or no. I could include a sample config JSON since that was mentioned. I'll keep everything flat without nested bullets or complex tables.**MVP Target Architecture Overview**

I should include the MVP target architecture in my response. It starts with agent definitions in a configuration format like this:

```json
{
  "default_provider": "openrouter",
  "providers": {
    "openrouter": {
      "base_url": "https://openrouter.ai/api/v1",
      "api_key_env": "OPENROUTER_API_KEY",
      "kind": "openai_chat"
    },
    "image": {
      "kind": "openai_images",
      "api_key_env": "OPENAI_API_KEY"
    }
  },
  "agents": {
    ...
  }
}
```

This config only stores the names of secret environment variables, which is good. I might also detail the model settings without naming exact models:

```json
"model": "anthropic/claude-sonnet-latest"
```

Using placeholders is a safe approach. I could include a pseudo flow for the calls, like this:

```python
for attempt <- 1..max_attempts:
  result = LLM.complete_json(agent, messages, schema)
  case result:
    tool_requests -> execute allowed tools
    patch -> validate/apply
    done -> return
```

This structure provides clarity for the implementation.**Designing Agent APIs and Tool Surfaces**

I need to outline a table for Agent APIs and tool surfaces, which includes:

- **State:** retrieve/book/page/element/history
- **Mutation:** create/update element, update metadata, create layout version
- **Media:** generate_image, inspect_image
- **Preview:** render_page, validate_layout, export_pdf
- **Search:** optional web_search

I should ensure subagents only access whitelisted tools to prevent unintended changes. For credential storage, `.env` is acceptable for development but not committed, and we’ll provide a `.env.example` for future reference. Using `System.fetch_env!` is necessary, and per-user encrypted `provider_credentials` would be added later. 

I need to implement OpenAPI specs for the app, focusing on the agents' tools in JSON schema. Lastly, considering a database backend, SQLite with WAL, no BLOBs, and append-only versions is a good approach for migrations.**Implementing Agentic Systems and Validation Feedback**

If I choose Phoenix and Elixir for this project, using Postgres would simplify the implementation of durable background queues like Oban. It’s crucial to ensure that the agentic system operates independently of the API/UI, keeping core modules free of Phoenix dependencies.

For the layout agent, I need to ensure it returns the page layout with proper validation feedback. If validation fails, diagnostics should include element ID, rule, and measured value. I’ll limit repair cycles to 2-3 attempts, and if it still fails, I'll surface the issues to the user while saving the candidate layout as a draft marked invalid.

Content validation feedback should follow a similar approach. I think it’s important to version after every prompt per TDD. However, if a validator loop modifies multiple pages, I recommend that each run creates a single committed version per changed object after validation, storing intermediate candidates in a run log instead of cluttering the element history. This ensures that new versions are created after each prompt for layouts and content, aligning with TDD practices.**Defining Design Decisions and Database Structure**

It seems I’m considering that validations occur after each prompt run, rather than after each subagent attempt. I should clarify that this is a design decision, emphasizing that not every retry will lead to a change. 

Maintaining content/layout separation is important. As for database tables, I could keep it simple with structures like `books`, `pages`, `elements`, `element_versions`, `layout_versions`, `assets`, `agent_runs`, and `agent_steps`. I don’t need to get into schema details.

The backend will make the calls, sending high-level prompts without exposing external LLM credentials. For external model providers, I’ll use OpenRouter for text, considering direct OpenAI or Anthropic options later. Image generation shouldn't go through OpenRouter unless it's tested, so I'll select a direct image API. Lastly, web search is optional via Tavily or Brave, but using no web for demo purposes is preferable.**MVP Risk Assessment and Next Steps**

I need to consider the MVP risks, particularly that provider variation poses the biggest challenge. I can mitigate this by using schemas and capability flags. Additionally, layout measurements need a real render engine; I shouldn't rely on the LLM to guess.

For the next step, I should ask the user for confirmation. If these decisions sound right, I would proceed to write the implementation plan for the agentic system and define module boundaries.

Finally, as stated in AGENTS.md, the MVP, PRD/TDD draft must be confirmed, with a reminder to keep interfaces lightweight. Let's wrap this up at the desired verbosity.

AGENTS.md confirms the key constraint: this is an MVP, PRD/TDD are draft guidance, and major choices like language/framework need explicit confirmation.

**Recommendation**
Use a lightweight custom agent runtime, not a heavy agent framework.

For the MVP I would choose:

| Area | Recommendation |
|---|---|
| Agent runtime | Custom orchestrator with role-based subagents, JSON schemas, tool registry, validation loops |
| Text LLM API | OpenRouter using OpenAI-compatible chat/completions |
| Image generation | Separate provider adapter, likely OpenAI Images, Replicate, Stability, or similar |
| Language/framework | Elixir + Phoenix, pending your confirmation |
| DB | SQLite via Ecto, with filesystem asset storage |
| Credentials | Env vars as source of truth, `.env` only for local dev |
| Agent config | Secretless `agents.json` mapping agent names to provider/model/settings |

**Agent Set**
I would keep the first version small:

| Agent | Purpose | Writes? | Notes |
|---|---|---:|---|
| Orchestrator | Interprets user intent, decides which subagents run, manages validation/commit | No direct content writes | Strong reasoning model |
| Research / Book Planner | Maintains book brief, audience, theme, outline, style constraints | Book metadata only | Web search optional, probably off for first demo |
| Content Agent | Writes/edits text, page concepts, image prompts, element assignments | Content elements | Works page-by-page |
| Media Agent | Generates/refines images, stores assets, validates image suitability | Media assets | Separate because image APIs differ |
| Layout Agent | Places elements on page, proposes layout JSON | Layout versions | Should not edit content |
| Content Validator | Critiques story/content against brief, age, continuity, theme | No | Can be a cheap/fast model later |
| Layout Validator | Deterministic layout checks | No | Not an LLM agent initially |

Important distinction: the validators should not be autonomous writers. They return issues. The writer/layout agents repair from those issues.

**Call Model**
I would not let LLMs call DB or external APIs directly.

Use a backend-controlled loop:

```text
UI/API prompt
  -> create agent run
  -> load book/page context
  -> Orchestrator produces structured plan
  -> run subagents with scoped context
  -> subagents return structured tool requests or patch proposals
  -> backend executes allowed tools
  -> validators return issues
  -> repair loop if needed
  -> commit new versions
  -> emit UI/websocket diff
```

The key runtime primitive should be something like:

```text
run_agent(agent_name, task, context) -> structured_result
```

Where `structured_result` is one of:

```json
{
  "type": "tool_requests",
  "calls": [
    {
      "tool": "get_page",
      "args": { "page_id": "..." }
    }
  ]
}
```

```json
{
  "type": "patch_proposal",
  "patch": {
    "content_changes": [],
    "layout_changes": []
  }
}
```

```json
{
  "type": "final_response",
  "message": "..."
}
```

This is more portable than relying entirely on provider-native tool calling.

**OpenAPI / OpenAI Compatibility**
There are two related but different ideas here:

| Thing | Support Reality |
|---|---|
| OpenAPI REST specs | Not universally consumed/executed by model providers |
| OpenAI-compatible chat API | Widely supported, but not perfectly uniform |
| OpenAI-style tool/function calling | Supported by many models/providers, inconsistent across models |
| JSON schema structured output | Supported by some providers/models, inconsistent |
| Image generation | Not standardized across OpenAI-compatible APIs |

For the demo, OpenRouter is a good cheat because it gives one OpenAI-compatible entry point for many text models.

But I would still design the app with a provider adapter:

```text
LLM.complete_json(agent_name, messages, schema)
LLM.complete_text(agent_name, messages)
Media.generate_image(provider_name, prompt, options)
```

This lets us swap OpenRouter for direct OpenAI/Anthropic/Gemini/etc later.

For tool calls, I would initially use our own JSON action format plus server-side validation. Provider-native tool calling can be added later as an optimization.

**Internal APIs**
The agents should use a small internal tool registry, not broad app access.

Initial tools:

| Tool Group | Tools |
|---|---|
| State | `get_book`, `get_outline`, `get_page`, `get_page_elements`, `get_element`, `get_history` |
| Content | `create_element`, `update_text_element`, `update_element_metadata`, `assign_element_to_page` |
| Media | `generate_image`, `store_asset`, `inspect_image`, `lookup_asset` |
| Layout | `get_layout`, `propose_layout`, `validate_layout`, `render_preview` |
| Project | `update_book_brief`, `update_page_metadata` |
| Optional | `web_search` |

The deterministic Element/Layout APIs remain the real source of truth. Agents only request actions through typed tools.

**Validation Loops**
Content validation should be partly deterministic and partly LLM-based.

Content validator checks:

| Check | Type |
|---|---|
| Fits project brief/theme | LLM |
| Age appropriate | LLM |
| Continuity/order | LLM |
| Page text length | Deterministic |
| Required elements present | Deterministic |
| No unexpected structural edits | Deterministic |

Layout validation should be deterministic first.

Layout validator checks:

| Check | Type |
|---|---|
| Element inside page bounds | Deterministic |
| Safe margins / bleed | Deterministic |
| Text overflow | Deterministic render/measure |
| Minimum font size | Deterministic |
| Image resolution/DPI | Deterministic |
| Overlap/collision | Deterministic |
| Visual aesthetic critique | Optional multimodal later |

For MVP, I would not use an LLM to judge basic layout correctness. Have the layout agent propose, deterministic validator diagnose, layout agent repair.

Use max retries, probably 2 or 3. If still invalid, return the best candidate plus explicit validation failures.

**Versioning**
I would treat one user prompt as one committed version boundary.

That means:

| Event | Persisted? |
|---|---|
| Intermediate agent attempts | Agent run log only |
| Failed validation candidates | Agent run log, maybe debug table |
| Final accepted content/layout | New version rows |
| User-visible history | Only committed versions |

This avoids polluting user history with every failed repair attempt.

Each committed version should include:

```text
run_id
agent_name
prompt/user_intent
parent_version
created_at
validation_status
```

**Credentials**
Use environment variables as the actual secret store.

For local dev, `.env` is fine if it is never committed. The app can load it in dev only.

The config should store env var names, not secrets:

```json
{
  "providers": {
    "openrouter": {
      "kind": "openai_chat",
      "base_url": "https://openrouter.ai/api/v1",
      "api_key_env": "OPENROUTER_API_KEY"
    },
    "image": {
      "kind": "image_generation",
      "api_key_env": "IMAGE_API_KEY"
    }
  },
  "agents": {
    "orchestrator": {
      "provider": "openrouter",
      "model": "REPLACE_WITH_MODEL",
      "temperature": 0.2,
      "max_retries": 2
    },
    "content": {
      "provider": "openrouter",
      "model": "REPLACE_WITH_MODEL",
      "temperature": 0.7,
      "max_retries": 2
    },
    "layout": {
      "provider": "openrouter",
      "model": "REPLACE_WITH_MODEL",
      "temperature": 0.3,
      "max_retries": 3
    },
    "content_validator": {
      "provider": "openrouter",
      "model": "REPLACE_WITH_MODEL",
      "temperature": 0.1,
      "max_retries": 1
    }
  }
}
```

Later, if users bring their own keys, store encrypted per-user credentials. For the demo, do not store API keys in SQLite.

**Language / Framework**
My recommendation is Elixir + Phoenix unless you want to prioritize Python agent ecosystem over BEAM preference.

Why Elixir works well here:

| Strength | Relevance |
|---|---|
| Supervision/concurrency | Multiple page agents, image jobs, websocket progress |
| Phoenix Channels | Good fit for UI updates/diffs |
| Ecto | Clean SQLite/Postgres path |
| Functional core | Nice fit for deterministic tools/validators |
| Long-running processes | Agent runs can be supervised cleanly |

Main downside: fewer mature agent frameworks than Python.

But I do not think we need LangChain/CrewAI-style machinery for this MVP. The required system is mostly:

```text
prompts + schemas + model calls + tool registry + validation loop + persistence
```

That is manageable directly in Elixir.

If choosing Python instead, I would look at FastAPI + Pydantic + LangGraph or PydanticAI. Python is stronger if we want prebuilt agent workflow tooling, but it adds less value if we keep the agent layer simple.

I would not choose TypeScript solely for UI code sharing. The shared contract should be JSON/OpenAPI schemas, not shared runtime code.

**DB Backend**
SQLite is appropriate for the demo.

Use:

| Data | Storage |
|---|---|
| Books/pages/elements/layout metadata | SQLite |
| Text versions | SQLite |
| Layout versions | SQLite JSON columns or normalized rows |
| Agent runs/steps/tool calls | SQLite |
| Binary images/assets | Filesystem |
| Rendered previews/exports | Filesystem, referenced from SQLite |

Use SQLite WAL mode. Keep images out of the DB.

If we later need multi-user concurrency, durable queues, or production hosting, Postgres becomes the obvious migration target. In Elixir specifically, durable background job libraries are stronger with Postgres, so SQLite implies simpler supervised tasks for the MVP.

**Proposed Decisions To Confirm**
I’d use these as the first explicit architecture decisions:

1. Backend and agent runtime: `Elixir + Phoenix`.
2. Agent framework: custom lightweight runtime, no LangChain/CrewAI equivalent.
3. Text models: OpenRouter first, through a provider abstraction.
4. Tool calling: provider-native tool calling (OpenAI-style `tools`/`tool_calls` for OpenRouter, `functionDeclarations` for Gemini). Each provider adapter translates internal `Message`/`ToolCall`/`ToolResult` structs to the native format. More reliable, fewer tokens, still swappable via provider adapter.
5. Image generation: separate provider adapter, not assumed to be OpenRouter.
6. Credentials: env vars, `.env` only for local development.
7. DB: SQLite plus filesystem assets.
8. Validation: LLM content validator, deterministic layout validator.

The biggest open question is image generation: should the first demo actually generate images, or should it generate image prompts/placeholders first and add real image generation immediately after?

---

## Implementation Session 2026-06-01

**Provider abstraction and LLM integration**

### Decisions

1. **Provider-native tool calling** — Use each provider's native tool/function calling API rather than a JSON action loop. Provider adapters translate internal `Message`/`ToolCall`/`ToolResult` structs to provider-native format. More reliable, fewer tokens, still swappable.

2. **Three providers** — Mock (for tests), Gemini (Google AI), OpenRouter (OpenAI-compatible chat). Provider adapter modules implement `Slidething.LLM.Provider` behaviour with `complete_json/2` callback.

3. **Agent config** — `config/agents.json` maps agent types to provider/model settings. Loaded at startup by `Slidething.Agent.Config` GenServer. No secrets in config; keys from env vars (`GOOGLE_API_KEY`, `OPENROUTER_API_KEY`).

4. **`call_id` on ToolCall/ToolResult** — Added to support OpenAI-style tool call correlation. Gemini ignores it. Mock ignores it. Backward compat with existing structs (defaults to nil).

### Architecture

```
Agent.GenServer.handle_info(:do_llm_call)
  → LLM.Client.complete_json(agent_spec, messages)
    → dispatches on agent_spec.provider
      → Provider.Mock.complete_json/2
      → Provider.Gemini.complete_json/2
      → Provider.OpenRouter.complete_json/2
    → returns {:tool_requests, [ToolCall]} | {:patch_proposal, patch} | {:final_response, msg}
```

### Files

| File | Purpose |
|---|---|
| `config/agents.json` | Secretless agent→provider/model config |
| `lib/slidething/llm/provider.ex` | `@callback complete_json(agent_spec, [Message]) :: result` |
| `lib/slidething/llm/provider/mock.ex` | Existing mock logic extracted |
| `lib/slidething/llm/provider/gemini.ex` | Google Gemini `generateContent` API |
| `lib/slidething/llm/provider/openrouter.ex` | OpenAI-compatible chat/completions via OpenRouter |
| `lib/slidething/llm/client.ex` | Dispatches `complete_json/2` by `AgentSpec.provider` |
| `lib/slidething/agent/config.ex` | GenServer loading/watching `agents.json` |

### Dependencies added

- `req` ~> 0.5 (HTTP client for provider API calls)

---

## Implementation Session 2026-06-01 — Phase 2

**WebSocket communication design**

### Architecture

One Phoenix Channel per book: `"book:#{book_id}"`. Single topic with a `type` field discriminator on each message. The BookChannel GenServer bridges PubSub events (internal) to client-facing websocket messages.

```
Client (paged.js) ─── join "book:<id>" ─── BookChannel GenServer
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   on join:            subscribes to        subscribes to
   HTTP GET           PubSub events         PubSub events
   full state        "run_events:*"        "agent_events:*"
```

Initial page load via REST: `GET /api/books/:id` returns full tree. Websocket delivers only changes after that point.

### Topics

One per book: `"book:#{book_id}"`. No subtopics. Simpler than nested routing.

### Server → Client messages

| `type` | Payload | When |
|---|---|---|
| `book_state` | `{book, pages, elements, layout}` | Initial channel join |
| `element_added` | `{page_id, element}` | Agent creates element |
| `element_updated` | `{element_id, content, metadata}` | Agent/user edits text |
| `element_removed` | `{element_id}` | Element deleted |
| `element_reordered` | `{page_id, order: [element_id]}` | Reorder |
| `layout_updated` | `{page_id, element_layouts}` | Layout agent produces new layout |
| `run_progress` | `{run_id, phase, status}` | Orchestrator phase changes |
| `asset_ready` | `{element_id, asset_url}` | Image generation completes |

### Client → Server messages

| `type` | Payload | When |
|---|---|---|
| `prompt` | `{run_id?, prompt, target_id?}` | User sends prompt |
| `edit_element` | `{element_id, content}` | User edits text in-place |
| `move_element` | `{element_id, bounding_box}` | User drags element |
| `lock_element` | `{element_id}` | User locks from regeneration |
| `reorder_pages` | `{order: [page_id]}` | User reorders pages |

### Diff semantics

Never send full book on every change. `element_updated` sends only `element_id`, new `content`, and optionally changed `metadata`. `layout_updated` sends the full `element_layouts` array for one page. PubSub events are internal-only; the BookChannel transforms them into client-facing message types.

### BookChannel state

- On receiving PubSub events: transforms into client-facing message types, pushes to socket

---

## Implementation Session 2026-06-01 — Phase 3

**Database schema**

### Decisions

1. **Single elements table** with `element_type` discriminator (`text`, `title`, `image`, `caption`) rather than separate text/media tables. Flexible, fewer joins, easy to add types.

2. **Per-element content versioning, per-page layout versioning.** Each `content_change` creates a new `element_versions` row. Layout is versioned atomically per page (one `layout_versions` row). Run-level version boundary: one run = one new version per affected element/layout.

3. **`prompt_targets` join table** for querying prompt history by page/element. No JSON array hacks. `run_id` links prompts to the versions they produced.

4. **No Ecto migrations.** Tables created programmatically at startup via raw SQL. Schema modules use embedded schemas or plain maps; no Ecto schemas with `schema` macro binding to migrations.

### Tables

```
books
  id            TEXT PRIMARY KEY  -- UUID
  title         TEXT
  metadata      TEXT              -- JSON: theme, target_audience, style
  created_at    TEXT              -- ISO-8601
  updated_at    TEXT

pages
  id            TEXT PRIMARY KEY  -- UUID
  book_id       TEXT NOT NULL REFERENCES books(id)
  position      INTEGER NOT NULL  -- ordering
  metadata      TEXT              -- JSON: description, status
  created_at    TEXT
  updated_at    TEXT

elements
  id            TEXT PRIMARY KEY  -- UUID
  page_id       TEXT NOT NULL REFERENCES pages(id)
  element_type  TEXT NOT NULL     -- text | title | image | caption
  position      INTEGER NOT NULL  -- ordering within page
  locked        INTEGER DEFAULT 0 -- 1 if user locked from regeneration
  created_at    TEXT
  updated_at    TEXT

element_versions
  id            TEXT PRIMARY KEY  -- UUID
  element_id    TEXT NOT NULL REFERENCES elements(id)
  version       INTEGER NOT NULL
  run_id        TEXT              -- which run produced this
  content       TEXT              -- for text/title/caption
  asset_path    TEXT              -- filesystem path for images
  prompt        TEXT              -- prompt that generated this version
  metadata      TEXT              -- JSON: content_type, style, etc
  created_at    TEXT

formats
  id            TEXT PRIMARY KEY  -- UUID
  name          TEXT NOT NULL
  unit          TEXT NOT NULL     -- cm | pt
  width         REAL NOT NULL
  height        REAL NOT NULL

layout_versions
  id            TEXT PRIMARY KEY  -- UUID
  page_id       TEXT NOT NULL REFERENCES pages(id)
  format_id     TEXT NOT NULL REFERENCES formats(id)
  version       INTEGER NOT NULL
  run_id        TEXT
  element_layouts TEXT            -- JSON: [{element_id, bounding_box, style}]
  created_at    TEXT

prompts
  id            TEXT PRIMARY KEY  -- UUID
  book_id       TEXT NOT NULL REFERENCES books(id)
  run_id        TEXT NOT NULL
  agent_type    TEXT NOT NULL     -- orchestrator | planner | content | layout | media
  user_prompt   TEXT NOT NULL
  context       TEXT              -- JSON: freeform metadata
  result_summary TEXT
  created_at    TEXT

prompt_targets
  prompt_id     TEXT NOT NULL REFERENCES prompts(id)
  target_type   TEXT NOT NULL     -- page | element
  target_id     TEXT NOT NULL
  UNIQUE(prompt_id, target_type, target_id)
```

### Indexes

```
CREATE INDEX idx_pages_book ON pages(book_id);
CREATE INDEX idx_elements_page ON elements(page_id);
CREATE INDEX idx_element_versions_element ON element_versions(element_id);
CREATE INDEX idx_layout_versions_page ON layout_versions(page_id);
CREATE INDEX idx_prompts_book ON prompts(book_id);
CREATE INDEX idx_prompts_run ON prompts(run_id);
CREATE INDEX idx_prompt_targets_target ON prompt_targets(target_type, target_id);
```

### Versioning query patterns

Get prompt that produced element "elem-7" version 3:
```sql
SELECT p.* FROM prompts p, element_versions ev
WHERE ev.element_id = 'elem-7' AND ev.version = 3
  AND p.run_id = ev.run_id
```

Get full prompt lineage for an element:
```sql
SELECT p.user_prompt, ev.version FROM prompts p
JOIN element_versions ev ON ev.run_id = p.run_id
JOIN prompt_targets pt ON pt.prompt_id = p.id
WHERE pt.target_id = 'elem-7' AND pt.target_type = 'element'
ORDER BY ev.version ASC
```

Get relevant prompt history for agent context (page level):
```sql
SELECT DISTINCT p.* FROM prompts p
JOIN prompt_targets pt ON pt.prompt_id = p.id
WHERE p.book_id = ? AND pt.target_id = 'page-3'
ORDER BY p.created_at DESC LIMIT 10
```

### Seed data

One default format on startup:
```sql
INSERT INTO formats (id, name, unit, width, height)
VALUES ('format-default', 'Children Book Square', 'cm', 20.0, 20.0)
```

---

## Implementation Session 2026-06-01 — Phase 4

**PubSub event bus, Phoenix Channels, mix task, asset storage**

### PubSub event bus

All agent runs broadcast to three PubSub topics:

| Topic | Content |
|---|---|
| `run_events:#{run_id}` | Phase transitions, completion, failure |
| `agent_events:#{run_id}` | LLM calls, tool execution per-run |
| `agent_events:all` | Cross-run tool result monitoring |

Every consumer (Channel, mix task, future MCP server) subscribes to the same topics. No translation layers — each is a thin PubSub subscriber.

### Phoenix Channels (browser UI)

- **`SlidethingWeb.UserSocket`** — `socket "/socket"`, connect all for MVP (no auth)
- **`SlidethingWeb.RunChannel`** — topic `"run:{run_id}"`
  - `join/3` — subscribes to `run_events:#{id}` and `agent_events:#{id}`
  - `handle_in "prompt", ...` — start a new run from the browser (bidirectional)
  - `handle_info` — relays PubSub events to socket client as `push("run_event", ...)` or `push("agent_event", ...)`

Future: `"book:{book_id}"` channel for state sync (element diffs, layout changes) as described in Phase 2 design.

### Mix task

```
mix generate "Create a 5-page children's book about a fox"
```

Starts the full OTP app, calls `API.start_run/2`, subscribes to PubSub directly (no HTTP), prints events with icons in real time. Blocks until completion. Provider can be set via `--provider` flag or `SLIDETHING_PROVIDER` env var.

### Runtime provider switching

- `Slidething.Agent.Config.set(:agent_name, provider: "gemini", model: "gemini-2.5-flash")` — per-agent override at runtime
- `SLIDETHING_PROVIDER` env var — overrides all agents on startup without editing files
- `Slidething.Agent.Config.reset/0` — reload from `config/agents.json`

### Media storage

- `Slidething.AssetStore` — filesystem storage under `$XDG_DATA_HOME/slidething/media` (`~/.local/share/slidething/media`)
- Test env: `/tmp/slidething_test_media`, wiped on startup via `clean!/0`
- No MIME type filtering — accept anything the browser can display
- UUID filenames (preserving original extension), no collision risk
- Operations: `store/2`, `store_from_path/1`, `retrieve/1`, `retrieve_meta/1`, `delete/1`
