defmodule Slidething.Schema.Format do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          unit: String.t(),
          width: float(),
          height: float()
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "formats" do
    field :name, :string
    field :unit, :string
    field :width, :float
    field :height, :float
  end
end