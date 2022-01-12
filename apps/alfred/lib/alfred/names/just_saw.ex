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

  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      @behaviour Alfred.JustSaw
      @use_opts use_opts

      # Alfred.JustSaw.put_callbacks_attribute(__MODULE__, unquote(use_opts))

      @doc false
      def callbacks, do: Alfred.JustSaw.callbacks_for_module(__MODULE__)

      def just_saw(names, opts \\ []) do
        callbacks() |> Alfred.JustSaw.just_saw(names, opts)
      end
    end
  end

  @callback callbacks() :: %{:execute => any(), :status => any()}
  @callback just_saw(String.t() | map() | list(), list()) :: :ok

  # NOTE: unused at present
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:callbacks_defined, 1}) do
      callbacks =
        %{
          status: Module.defines?(env.module, {:status, 2}),
          execute: Module.defines?(env.module, {:execute, 2})
        }
        # Macro.escape/1 converts map into AST for direct insertion via unquote
        |> Macro.escape()

      quote do
        def callbacks_defined, do: unquote(callbacks)
        defoverridable callbacks_defined: 0
      end
    end
  end

  #
  # Alfred.JustSaw implementation
  #

  @doc false
  def callbacks_for_module(module) do
    use_opts_callbacks = get_in(module.__info__(:attributes), [:use_opts, :callbacks]) || []
    functions = Keyword.take(module.__info__(:functions), [:execute, :status])

    Enum.reduce(functions, %{execute: false, status: false}, fn
      {func, 2}, acc -> Map.put(acc, func, get_in(use_opts_callbacks, [func]) || {module, 2})
      _, acc -> acc
    end)
  end

  @doc since: "0.3.0"
  def just_saw(callbacks, name, opts) when is_binary(name), do: just_saw(callbacks, [name], opts)

  def just_saw(callbacks, names, opts) when is_list(names) do
    opts_all = [{:callbacks, callbacks} | opts]

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

  @doc false
  def put_callbacks_attribute(module, use_opts) do
    callback = Keyword.get(use_opts, :callbacks, module)

    Module.put_attribute(module, :alfred_callbacks, callback)
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
