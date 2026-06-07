defmodule Slidething.Agent do
  @moduledoc """
  Core agent types and structs for the agentic system.
  """

  defmodule AgentSpec do
    @moduledoc """
    Specification for an agent type (planner, content, layout, etc.).
    """
    defstruct [
      :name,
      :provider,
      :model,
      :temperature,
      :max_tokens,
      :max_iterations,
      :system_prompt,
      :tools,
      :image_provider,
      :image_model,
      tool_choice: nil
    ]

    @type t :: %__MODULE__{
            name: atom(),
            provider: String.t(),
            model: String.t(),
            temperature: float(),
            max_tokens: integer(),
            max_iterations: integer(),
            system_prompt: String.t(),
            tools: [atom()],
            image_provider: String.t() | nil,
            image_model: String.t() | nil,
            tool_choice: String.t() | nil
          }
  end

  defmodule Message do
    @moduledoc """
    LLM conversation message.
    """
    defstruct [:role, :content, :tool_calls, :tool_results]

    @type t :: %__MODULE__{
            role: :system | :user | :assistant | :tool,
            content: String.t() | nil,
            tool_calls: [ToolCall.t()] | nil,
            tool_results: [ToolResult.t()] | nil
          }
  end

  defmodule ToolCall do
    @moduledoc """
    Tool call requested by LLM.
    """
    defstruct [:call_id, :tool, :args]

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            tool: atom(),
            args: map()
          }
  end

  defmodule ToolResult do
    @moduledoc """
    Result of tool execution.
    """
    defstruct [:call_id, :tool, :success, :data, :error]

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            tool: atom(),
            success: boolean(),
            data: term() | nil,
            error: String.t() | nil
          }
  end

  defmodule SubagentTask do
    @moduledoc """
    Task for a subagent within a phase.
    """
    defstruct [:agent, :scope, :instruction, :phase_name, context: %{}]

    @type scope ::
            :book
            | {:page, String.t()}
            | {:pages, [String.t()]}
            | {:element, String.t()}
            | {:elements, [String.t()]}

    @type t :: %__MODULE__{
            agent: :research | :content | :layout | :media,
            scope: scope(),
            instruction: String.t(),
            phase_name: String.t() | nil,
            context: map()
          }
  end

  defmodule ValidationIssue do
    @moduledoc """
    Validation issue found by validators.
    """
    defstruct [:severity, :source, :target_id, :rule, :message, :measured_value, :expected_value]

    @type t :: %__MODULE__{
            severity: :error | :warning,
            source: :content | :layout,
            target_id: String.t(),
            rule: String.t(),
            message: String.t(),
            measured_value: term() | nil,
            expected_value: term() | nil
          }
  end
end
