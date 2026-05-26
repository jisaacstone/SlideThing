
Table of Content

* API
* Internal Representation
* Agent Structure

# API

## Agentic API

These calls are routed thought an agentic system

### Create

The main interface. Inputs:

* Prompt. Required. The new prompt describing the desired user action
* Id. Optional. Constrain action to only deal with an explicit existing item in the internal representation.
Can be book-id, page-id, element-id

### Refine

Specifically for formatting and validation. This will only update layout, not content.

* Prompt. Required. New layout-specific prompt
* Id. Optional. Book, page or element id. Multiple ids can be provided

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

We will have two tables for elements

Media:
Id: UUID
Version: Int
Metadata:
  Prompt: String
  Content-Type: String

Text:
Id: UUID
Version: Int
Content: String
Metadata:
  Prompt: String
  Etc

Layout happens at the page level. We reference the Format table

Format:
Id: UUID
Unit: cm | pt
Width: Float
Height: Float

Layout:
FormatId: UUID
PageId: UUID
Version: Int
ElementLayouts:
  ElementId: UUID
  BoundingBox: (Point, Point)
  Etc

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

We have a tree of agents.

At the top level is the Orchestrator. It takes user input, calls subagents, and returns a response.

Below the Orchestrator are the Research, Content, Layout subagents.

           +------------------+
           |   Orchestrator   |
           +------------------+
             |       |       |
    +----------+-----------+----------+
    | Research |  Content  |  Layout  |
    +----------+-----------+----------+

The Research agent is our global planner. It makes project-wide decisions, searches the web, and is responsible for major theme and formatting decisions.

Required tools: Web Search, Book table CRUD operations, get-outline, get-content, preview
Required model capabilities: Reasoning

The Content agent is responsible for all content elements. The actual images and text. This agent also assigns these elements to specific pages.

Required tools: media-lookup, media-creation, get-page-elements, get-element, CRUD element operation
Media queries require image capable models - these can be a separate subagent.

The Layout agent takes the content and lays it out on the page.

Content and Layout agents work at the page level. So they can be run in parallel if multiple page edits are required by the orchestrator.

Content and Layout agents have a built in validation loop.
Content agent validates against the global requirements recorded by the Research agent.
Does this make sense, is it truthful, does it fit with the theme, is it in the correct order, etc
Layout validates with deterministic layout rules. Is the centering correct, does the text overflow, is it too small or too big, are the images of the correct resolution, etc.

After every prompt, the orchestrator agent creates a new version of all layouts and content.

# UI

The UI will be built on top of paged.js. A custom JS library will be built to allow the editing and movement of items on the page. We will also use paged.js to export to pdf, via headless browser. This allows high-fidelity between the UI and the final output.

The internal representation will be built on page load. A websocket will communicate changes between the client and server. Only diffs will be sent.

The user should be able to move things, edit text, and enter new prompts from the UI
