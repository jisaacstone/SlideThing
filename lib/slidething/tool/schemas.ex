defmodule Slidething.Tool.Schemas do
  @moduledoc """
  Shared JSON schemas for all tool function declarations.
  Used by provider adapters (Gemini, OpenRouter) to generate
  their provider-specific tool schemas.
  """

  @schemas %{
    create_book: %{
      name: "create_book",
      description:
        "Create a new book with title and metadata. Use this FIRST when generating a new book.",
      parameters: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "The book title"},
          metadata: %{type: "object", description: "Book metadata: theme, target_audience, style"}
        },
        required: ["title"]
      }
    },
    create_pages: %{
      name: "create_pages",
      description:
        "Create pages for a book. Pass either a count (integer) or a list of page descriptions.",
      parameters: %{
        type: "object",
        properties: %{
          book_id: %{type: "string", description: "The book ID to add pages to"},
          pages: %{
            type: "array",
            description: "List of page descriptors, each with position and metadata.description",
            items: %{
              type: "object",
              properties: %{
                position: %{type: "integer"},
                metadata: %{type: "object", properties: %{description: %{type: "string"}}}
              }
            }
          }
        },
        required: ["book_id", "pages"]
      }
    },
    get_book: %{
      name: "get_book",
      description: "Get the full book with all pages and elements",
      parameters: %{
        type: "object",
        properties: %{
          book_id: %{type: "string", description: "The book ID to retrieve"}
        },
        required: ["book_id"]
      }
    },
    get_outline: %{
      name: "get_outline",
      description: "Get the page outline for a book (page IDs and positions, no elements)",
      parameters: %{
        type: "object",
        properties: %{
          book_id: %{type: "string", description: "The book ID"}
        },
        required: ["book_id"]
      }
    },
    get_page_elements: %{
      name: "get_page_elements",
      description: "Get all elements on a specific page with their latest content",
      parameters: %{
        type: "object",
        properties: %{
          page_id: %{type: "string", description: "The page ID"}
        },
        required: ["page_id"]
      }
    },
    get_element: %{
      name: "get_element",
      description: "Get a single element with its version history",
      parameters: %{
        type: "object",
        properties: %{
          element_id: %{type: "string", description: "The element ID"}
        },
        required: ["element_id"]
      }
    },
    create_element: %{
      name: "create_element",
      description:
        "Create a new element on a page. Element types: 'title', 'text', 'image', 'caption'.",
      parameters: %{
        type: "object",
        properties: %{
          page_id: %{type: "string", description: "The page ID to add the element to"},
          element_type: %{
            type: "string",
            description: "Element type: title, text, image, caption"
          },
          content: %{
            type: "string",
            description:
              "The text content (for text/title/caption). For images, use an image prompt description."
          }
        },
        required: ["page_id", "element_type", "content"]
      }
    },
    update_element: %{
      name: "update_element",
      description: "Update an element's content (creates a new version)",
      parameters: %{
        type: "object",
        properties: %{
          element_id: %{type: "string", description: "The element ID to update"},
          content: %{type: "string", description: "The new content"}
        },
        required: ["element_id", "content"]
      }
    },
    update_book_metadata: %{
      name: "update_book_metadata",
      description: "Update book-level metadata (theme, audience, style)",
      parameters: %{
        type: "object",
        properties: %{
          book_id: %{type: "string", description: "The book ID"},
          metadata: %{type: "object", description: "Metadata key-value pairs"}
        },
        required: ["book_id", "metadata"]
      }
    },
    update_page_metadata: %{
      name: "update_page_metadata",
      description: "Update metadata on a specific page",
      parameters: %{
        type: "object",
        properties: %{
          page_id: %{type: "string", description: "The page ID"},
          metadata: %{type: "object", description: "Metadata key-value pairs"}
        },
        required: ["page_id", "metadata"]
      }
    },
    get_format: %{
      name: "get_format",
      description: "Get format dimensions (width, height, DPI, margins)",
      parameters: %{
        type: "object",
        properties: %{
          format_id: %{type: "string", description: "The format ID"}
        },
        required: ["format_id"]
      }
    },
    generate_image: %{
      name: "generate_image",
      description:
        "Generate an image from a prompt at the given aspect ratio. Returns an asset_path stored on disk. Follow with store_asset to attach it to the element.",
      parameters: %{
        type: "object",
        properties: %{
          prompt: %{type: "string", description: "Detailed image generation prompt"},
          aspect_ratio: %{
            type: "string",
            description:
              "Aspect ratio: one of '1:1', '9:16', '16:9', '3:4', '4:3'. Defaults to 1:1."
          }
        },
        required: ["prompt"]
      }
    },
    store_asset: %{
      name: "store_asset",
      description: "Store a generated image as an element version on a page",
      parameters: %{
        type: "object",
        properties: %{
          element_id: %{type: "string", description: "The element ID to attach the asset to"},
          asset_path: %{type: "string", description: "Path returned by generate_image"},
          prompt: %{type: "string", description: "The prompt used to generate the image"}
        },
        required: ["element_id", "asset_path"]
      }
    },
    get_recent_prompts: %{
      name: "get_recent_prompts",
      description:
        "Get recent edit prompts for a specific page or element, newest last. Useful for understanding recent changes and intent.",
      parameters: %{
        type: "object",
        properties: %{
          target_type: %{type: "string", description: "The target type: 'page' or 'element'"},
          target_id: %{type: "string", description: "The page or element ID"},
          limit: %{type: "integer", description: "Max number of prompts to return (default 5)"}
        },
        required: ["target_type", "target_id"]
      }
    },
    propose_layout: %{
      name: "propose_layout",
      description:
        "Persist a layout for a (page, format) pair. element_layouts is an array of {element_id, x, y, width, height}; coordinates are 0..1 fractions of the format dimensions.",
      parameters: %{
        type: "object",
        properties: %{
          page_id: %{type: "string", description: "The page ID"},
          format_id: %{type: "string", description: "The format ID, e.g. 'format-web'"},
          element_layouts: %{
            type: "array",
            description: "Per-element layout rectangles",
            items: %{
              type: "object",
              properties: %{
                element_id: %{type: "string"},
                x: %{type: "number"},
                y: %{type: "number"},
                width: %{type: "number"},
                height: %{type: "number"}
              },
              required: ["element_id", "x", "y", "width", "height"]
            }
          }
        },
        required: ["page_id", "format_id", "element_layouts"]
      }
    },
    submit_plan: %{
      name: "submit_plan",
      description: "Submit the execution plan. Call this once with your complete plan.",
      parameters: %{
        type: "object",
        properties: %{
          plan: %{
            type: "object",
            description: "The execution plan with context and phases.",
            properties: %{
              context: %{
                type: "string",
                description:
                  "Optional shared background for all agents: theme, constraints, style notes."
              },
              phases: %{
                type: "array",
                description: "List of phases to execute, with dependency graph.",
                items: %{
                  type: "object",
                  properties: %{
                    name: %{type: "string", description: "Unique phase name"},
                    step_type: %{
                      type: "string",
                      description: "agent | validator | coordinator | planner"
                    },
                    agent_type: %{
                      type: "string",
                      description:
                        "content | layout | media | validator | coordinator | planner | page_pipeline"
                    },
                    scope: %{type: "string", description: "book | per_page | per_element"},
                    depends_on: %{
                      type: "array",
                      items: %{type: "string"},
                      description: "List of phase names this depends on"
                    },
                    condition: %{
                      type: ["string", "null"],
                      description: "Condition to gate execution: null or has_layout_issues"
                    },
                    max_retries: %{type: "integer", description: "Max retries for this phase"},
                    context: %{
                      type: "object",
                      description: "Optional context/notes for the agent"
                    }
                  },
                  required: ["name", "step_type", "agent_type", "scope", "depends_on"]
                }
              }
            },
            required: ["phases"]
          }
        },
        required: ["plan"]
      }
    }
  }

  @doc """
  Get a tool schema by atom name. Returns nil for unknown tools.
  """
  def get(tool_name) when is_atom(tool_name) do
    Map.get(@schemas, tool_name)
  end

  @doc """
  List all known tool names.
  """
  def known_tools, do: Map.keys(@schemas)
end
