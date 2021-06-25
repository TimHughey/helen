defmodule Alfred.JustSaw do
  alias __MODULE__

  defmodule DevAlias do
    defstruct name: nil, ttl_ms: nil

    @type t :: %__MODULE__{
            name: String.t(),
            ttl_ms: pos_integer()
          }
  end

  defstruct mutable?: false,
            callback_mod: nil,
            seen_list: []

  @type t :: %__MODULE__{
          mutable?: boolean(),
          callback_mod: module(),
          seen_list: [DevAlias.t(), ...]
        }

  def add_device(%JustSaw{} = js, %{name: name, ttl_ms: ttl_ms}) do
    %JustSaw{js | seen_list: [%DevAlias{name: name, ttl_ms: ttl_ms}] ++ js.seen_list}
  end

  def new(callback_mod, mutable?), do: %JustSaw{mutable?: mutable?, callback_mod: callback_mod}
end
