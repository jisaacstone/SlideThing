defmodule Slidething.LLM.Provider do
  @moduledoc """
  Behaviour for LLM provider adapters.

  Each provider implements complete_json/2, which takes an AgentSpec
  and list of messages and returns structured results understood by
  the agent GenServer.
  """

  alias Slidething.Agent.Message

  @type result ::
          {:tool_requests, [Slidething.Agent.ToolCall.t()]}
          | {:patch_proposal, map()}
          | {:final_response, String.t()}
          | {:error, term()}

  @callback complete_json(
              Slidething.Agent.AgentSpec.t(),
              [Message.t()]
            ) :: result
end