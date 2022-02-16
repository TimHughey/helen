defmodule AlfredSim do
  ##
  ## Alfred.Execute
  ##

  def execute({opts, overrides} = args_tuple) when is_list(opts) and is_list(overrides) do
    args = Alfred.Execute.Args.auto(args_tuple) |> Enum.into(%{})
    execute = Alfred.Name.invoke(args, :execute)

    unless GenServer.whereis(self()), do: Process.send(self(), {:echo, execute}, [])

    execute
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
  defdelegate notify_register(name, opts), to: Alfred.Notify, as: :register
  defdelegate notify_unregister(opts), to: Alfred.Notify, as: :unregister

  ##
  ## Alfred.Status delegation
  ##

  def status(<<_::binary>> = name, opts \\ []) do
    args = Enum.into(opts, %{}) |> Map.put(:name, name)

    Alfred.Name.invoke(args, :status)
  end
end
