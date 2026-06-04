defmodule Slidething.Schema.Prompt do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          book_id: String.t(),
          user_prompt: String.t(),
          target_type: String.t() | nil,
          target_id: String.t() | nil,
          status: String.t(),
          result_summary: String.t() | nil,
          completed_at: DateTime.t() | nil,
          created_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "prompts" do
    field :book_id, :string
    field :user_prompt, :string
    field :target_type, :string
    field :target_id, :string
    field :status, :string, default: "running"
    field :result_summary, :string
    field :completed_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
  end
end
