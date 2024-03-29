defmodule Alfred do
  @moduledoc """
  Master of known names
  """

  # coveralls-ignore-start

  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      Alfred.register_attribute(__MODULE__)
      @_alfred_features_ [:execute, :track]

      use Alfred.Status

      execute_opts = Keyword.get(use_opts, :execute)
      if execute_opts, do: use(Alfred.Execute, execute_opts)

      name_opts = Keyword.get(use_opts, :name, [])
      use Alfred.Name, name_opts
    end
  end

  @mod_attribute :alfred_use_opts
  @doc false
  def put_attribute(module, use_opts) do
    Module.register_attribute(module, @mod_attribute, persist: true)

    [
      callback: Keyword.get(use_opts, :callback, :module),
      execute: Keyword.get(use_opts, :execute, :not_supported),
      status: Keyword.get(use_opts, :status, :not_supported),
      track: Keyword.get(use_opts, :track, :opt_out)
    ]

    Module.put_attribute(module, @mod_attribute, use_opts)
  end

  def register_attribute(module) do
    Module.register_attribute(module, @mod_attribute, persist: true)
  end

  # coveralls-ignore-stop

  ##
  ## Alfred.Execute
  ##

  def execute({opts, overrides} = args_tuple) when is_list(opts) and is_list(overrides) do
    args_tuple
    |> Alfred.Execute.Args.auto()
    |> Enum.into(%{})
    |> Alfred.Name.invoke(:execute)
  end

  def execute(opts) when is_list(opts), do: execute(opts, [])
  def execute(opts, overrides), do: execute({opts, overrides})
  def execute_off(name, opts \\ []), do: execute([name: name, cmd: "off"], opts)
  def execute_on(name, opts \\ []), do: execute([name: name, cmd: "on"], opts)
  defdelegate execute_to_binary(execute), to: Alfred.Execute, as: :to_binary

  ##
  ## Alfred.Name delegations
  ##

  defdelegate name_all_registered(), to: Alfred.Name, as: :registered
  defdelegate name_allowed_opts, to: Alfred.Name, as: :allowed_opts
  defdelegate name_available?(name), to: Alfred.Name, as: :available?
  defdelegate name_info(name), to: Alfred.Name, as: :info
  defdelegate name_missing?(name, opts \\ []), to: Alfred.Name, as: :missing?
  defdelegate name_registered?(name), to: Alfred.Name, as: :registered?
  defdelegate name_unregister(name), to: Alfred.Name, as: :unregister

  ##
  ## Alfred.Notify delegations
  ##

  defdelegate notify_register(opts), to: Alfred.Notify, as: :register
  defdelegate notify_register(arg1, opts), to: Alfred.Notify, as: :register
  defdelegate notify_unregister(args), to: Alfred.Notify, as: :unregister

  ##
  ## Alfred.Status delegation
  ##

  def status(<<_::binary>> = name, opts \\ []) do
    args = Enum.into(opts, %{}) |> Map.put(:name, name)

    Alfred.Name.invoke(args, :status)
  end
end
