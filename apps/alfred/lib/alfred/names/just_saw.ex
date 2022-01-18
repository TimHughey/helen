defmodule Alfred.JustSaw do
  @moduledoc false

  @callback just_saw(String.t() | map() | list(), list()) :: :ok

  # coveralls-ignore-start

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
    Module.register_attribute(module, @mod_attribute, persist: true)
    Module.put_attribute(module, @mod_attribute, use_opts)
  end

  def allowed_opts, do: Alfred.Name.allowed_opts()

  # coveralls-ignore-stop

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

  def just_saw(name, module, opts) when is_binary(name) or is_map(name) do
    just_saw([name], module, opts)
  end

  def just_saw(names, module, opts) when is_list(names) do
    opts_all = [{:callbacks, callbacks(module)} | opts]

    Enum.each(names, fn name -> Alfred.Name.register(name, opts_all) end)
  end

  def just_saw(nil, _module, _opts), do: nil
end
