defmodule Eva.Variant.InRange do
  defstruct immutable: %{name: nil, value: nil},
            mutable: %{name: nil},
            in_range: %{max: nil, min: nil, tolerance: nil},
            valid?: true

  @type value_key() :: atom()
  @type t :: %__MODULE__{
          immutable: %{required(:name) => String.t(), required(:value) => value_key()},
          mutable: %{required(:name) => String.t()},
          in_range: %{required(:max) => float(), required(:min) => float(), tolerance: float()},
          valid?: boolean()
        }

  def new(x) do
    %__MODULE__{
      immutable: %{name: x.immutable.name, value: String.to_atom(x.immutable.value)},
      mutable: %{name: x.mutable.name},
      in_range: %{min: x.range.min, max: x.range.max, tolerance: x.range.tolerance},
      valid?: true
    }
  end
end
