defmodule Slidething.Schema.Format do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          unit: String.t(),
          width: float(),
          height: float(),
          dpi: integer(),
          bleed_mm: float() | nil,
          safe_margin_mm: float() | nil
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "formats" do
    field :name, :string
    field :unit, :string
    field :width, :float
    field :height, :float
    field :dpi, :integer, default: 300
    field :bleed_mm, :float
    field :safe_margin_mm, :float
  end
end
