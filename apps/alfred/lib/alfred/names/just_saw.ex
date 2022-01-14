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

  @callback just_saw(String.t() | map() | list(), list()) :: :ok

  @doc false
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      # NOTE: capture use opts for Alfred.JustSaw
      Alfred.JustSaw.put_attribute(__MODULE__, use_opts)

      @behaviour Alfred.JustSaw

      def just_saw(names, opts \\ []) do
        Alfred.JustSaw.just_saw(names, __MODULE__, opts)
      end
    end
  end

  @mod_attribute :alfred_just_saw_use_opts
  @doc false
  def put_attribute(module, use_opts) do
    Module.put_attribute(module, @mod_attribute, use_opts)
  end

  @doc false
  def callbacks(module) do
    use_opts = module.__info__(:attributes)[@mod_attribute]
    use_cb = use_opts[:callbacks] || []

    functions = module.__info__(:functions)
    defined_cb = Keyword.take(functions, [:execute, :status])

    Enum.reduce(defined_cb, %{execute: false, status: false}, fn
      {func, 2}, acc ->
        # NOTE: callbacks specified via use opts are giving highest precedence
        fa = Keyword.get(use_cb, func, {module, 2})
        Map.put(acc, func, fa)

      _, acc ->
        acc
    end)
  end

  @doc since: "0.3.0"
  def just_saw(name, module, opts) when is_binary(name) do
    just_saw([name], module, opts)
  end

  def just_saw(names, module, opts) when is_list(names) do
    opts_all = [{:callbacks, callbacks(module)} | opts]

    Enum.each(names, fn name -> Alfred.Name.register(name, opts_all) end)
  end

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
