defmodule Alfred.JustSaw do
  alias __MODULE__
  alias Alfred.SeenName

  defstruct mutable?: false,
            callback: {:unset, nil},
            seen_list: [],
            valid?: true

  @type callback_tuple() :: {:server, atom()} | {:module, module()} | mfa()
  @type t :: %__MODULE__{
          mutable?: boolean(),
          callback: callback_tuple(),
          seen_list: [SeenName.t(), ...],
          valid?: boolean()
        }

  def new_immutable(seen_list, map_seen_fn, {_type, _val} = callback)
      when is_list(seen_list)
      when is_function(map_seen_fn, 1),
      do: new(:immutable, seen_list, map_seen_fn, callback)

  def new_mutable(seen_list, map_seen_fn, {_type, _val} = callback)
      when is_list(seen_list)
      when is_function(map_seen_fn, 1),
      do: new(:mutable, seen_list, map_seen_fn, callback)

  def new(type, seen_list, map_seen_fn, callback) when type in [:immutable, :mutable] do
    %JustSaw{mutable?: type == :mutable, callback: callback, seen_list: Enum.map(seen_list, map_seen_fn)}
    |> validate()
  end

  def to_known_name(%JustSaw{valid?: false}), do: []

  def to_known_names(%JustSaw{callback: cb, mutable?: mut?} = js, opts \\ []) when is_list(opts) do
    alias Alfred.KnownName

    seen_list = SeenName.validate(js.seen_list)

    for %SeenName{valid?: true, name: n, seen_at: at, ttl_ms: t} <- seen_list do
      %KnownName{name: n, callback: cb, mutable?: mut?, seen_at: at, ttl_ms: t}
      |> KnownName.validate()
    end
  end

  def validate(%JustSaw{callback: cb} = js) do
    case cb do
      {what, x} when what in [:server, :module] and is_atom(x) -> js
      func when is_function(func) -> js
      _ -> %JustSaw{js | valid?: false}
    end
  end
end
