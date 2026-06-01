defmodule Slidething.Schema.LayoutVersion do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          page_id: String.t(),
          format_id: String.t(),
          version: integer(),
          run_id: String.t() | nil,
          element_layouts: [map()],
          created_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "layout_versions" do
    field :page_id, :string
    field :format_id, :string
    field :version, :integer
    field :run_id, :string
    field :element_layouts, {:array, :map}, default: []
    field :created_at, :utc_datetime_usec
  end
end