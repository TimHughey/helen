defmodule AlfredSim do
  def execute({_args, _opts} = tuple) do
    Alfred.execute(tuple)
    |> tap(fn execute -> Process.send(self(), {:echo, execute}, []) end)
  end

  def execute(<<_::binary>> = name, opts \\ []), do: Alfred.execute(name, opts)

  def notify_register(opts), do: Alfred.notify_register(opts)

  def notify_unregister(_), do: :ok

  def status(name, opts \\ []) do
    Alfred.status(name, opts)
  end
end
