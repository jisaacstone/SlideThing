defmodule Slidething.Schema.Book do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t() | nil,
          metadata: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "books" do
    field :title, :string
    field :metadata, :map, default: %{}
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end