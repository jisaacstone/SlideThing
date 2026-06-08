defmodule Slidething.Tool.Schemas do
  @moduledoc """
  Shared JSON schemas for all tool function declarations.
  Used by provider adapters (Gemini, OpenRouter) to generate
  their provider-specific tool schemas.
  """

  @schemas %{
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
      description: "Get a single element with its content",
      parameters: %{
        type: "object",
        properties: %{
          element_id: %{type: "string", description: "The element ID"}
        },
        required: ["element_id"]
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
                      description: "content | layout | media | validator | coordinator | planner"
                    },
                    scope: %{
                      type: "string",
                      description:
                        "book | per_page (content/media always use \"book\"; layout uses \"per_page\")"
                    },
                    config: %{
                      type: "object",
                      description:
                        "Phase-specific targeting and parameters. content/media phases MUST include this.",
                      properties: %{
                        op: %{type: "string", description: "\"create\" or \"update\""},
                        element_type: %{
                          type: "string",
                          description:
                            "For content create: \"title\", \"text\", \"caption\", etc."
                        },
                        element_id: %{
                          type: "string",
                          description: "For updates: the element ID to overwrite"
                        },
                        page_index: %{
                          type: "integer",
                          description:
                            "0-based index for new pages. First phase using an index creates the page; later phases reuse it."
                        },
                        page_id: %{type: "string", description: "Existing page ID for edit runs"},
                        aspect_ratio: %{
                          type: "string",
                          description:
                            "For media: image aspect ratio, e.g. \"1:1\", \"4:3\", \"16:9\". Defaults to \"1:1\"."
                        },
                        image_prompt: %{
                          type: "string",
                          description:
                            "For media: static style/art-direction prompt. Combined at runtime with subject derived from page text elements."
                        }
                      }
                    },
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
