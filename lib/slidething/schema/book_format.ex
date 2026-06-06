defmodule Slidething.Schema.BookFormat do
  use Ecto.Schema

  @type t :: %__MODULE__{
          book_id: String.t(),
          format_id: String.t()
        }

  @primary_key false
  schema "book_formats" do
    field :book_id, :string, primary_key: true
    field :format_id, :string, primary_key: true
  end
end
