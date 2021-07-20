defmodule Alfred.JustSaw do
  alias __MODULE__

  defmodule Alias do
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
          seen_list: [Alias.t(), ...]
        }

  def add_alias(%JustSaw{} = js, %{name: name, ttl_ms: ttl_ms}) do
    %JustSaw{js | seen_list: [%Alias{name: name, ttl_ms: ttl_ms}] ++ js.seen_list}
  end

  def new(callback_mod, mutable?), do: %JustSaw{mutable?: mutable?, callback_mod: callback_mod}

  def new(callback_mod, type, %{name: name, ttl_ms: ttl_ms}) when type in [:mutable, :immutable] do
    %JustSaw{
      mutable?: type == :mutable,
      callback_mod: callback_mod,
      seen_list: [%Alias{name: name, ttl_ms: ttl_ms}]
    }
  end

  def new(callback_mod, mutable?, details) when is_boolean(mutable?) and is_map(details) do
    new(callback_mod, if(mutable?, do: :mutable, else: :immutable), details)
  end
end
