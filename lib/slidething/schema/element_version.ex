defmodule Slidething.Schema.ElementVersion do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          element_id: String.t(),
          version: integer(),
          run_id: String.t() | nil,
          content: String.t() | nil,
          asset_path: String.t() | nil,
          prompt: String.t() | nil,
          metadata: map(),
          created_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "element_versions" do
    field :element_id, :string
    field :version, :integer
    field :run_id, :string
    field :content, :string
    field :asset_path, :string
    field :prompt, :string
    field :metadata, :map, default: %{}
    field :created_at, :utc_datetime_usec
  end
end