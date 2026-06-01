defmodule Slidething.Schema.Page do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          book_id: String.t(),
          position: integer(),
          metadata: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "pages" do
    field :book_id, :string
    field :position, :integer
    field :metadata, :map, default: %{}
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end