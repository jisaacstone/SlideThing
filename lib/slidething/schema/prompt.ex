defmodule Slidething.Schema.Prompt do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          book_id: String.t(),
          run_id: String.t(),
          agent_type: String.t(),
          user_prompt: String.t(),
          context: map(),
          result_summary: String.t() | nil,
          created_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "prompts" do
    field :book_id, :string
    field :run_id, :string
    field :agent_type, :string
    field :user_prompt, :string
    field :context, :map, default: %{}
    field :result_summary, :string
    field :created_at, :utc_datetime_usec
  end
end