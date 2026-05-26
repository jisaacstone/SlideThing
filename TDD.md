
Table of Content

* API
* Internal Representation

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

Layout happens at the page level. We reference the Format table

Format:
Id: UUID
Unit: cm | pt
Width: Float
Height: Float

Layout:
BookId: UUID
FormatId: UUID
Version: Int
ElementLaoyouts:
  ElementId: UUID
  BoundingBox: (Point, Point)
