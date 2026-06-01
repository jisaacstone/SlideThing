defmodule Slidething.Schema.PromptTarget do
  use Ecto.Schema

  @type t :: %__MODULE__{
          prompt_id: String.t(),
          target_type: String.t(),
          target_id: String.t()
        }

  @primary_key false
  schema "prompt_targets" do
    field :prompt_id, :string
    field :target_type, :string
    field :target_id, :string
  end
end