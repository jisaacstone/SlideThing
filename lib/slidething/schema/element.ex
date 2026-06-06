defmodule Slidething.Schema.Element do
  use Ecto.Schema

  @type element_type :: String.t()

  @type t :: %__MODULE__{
          id: String.t(),
          page_id: String.t(),
          element_type: String.t(),
          position: integer(),
          locked: boolean(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "elements" do
    field :page_id, :string
    field :element_type, :string
    field :position, :integer
    field :locked, :boolean, default: false
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end
