defmodule AlfredSim do
  alias Alfred.Notify.Ticket

  def execute(name, opts \\ []), do: Alfred.ExecAid.execute(name, opts)

  def notify_register(opts) do
    {:ok, %Ticket{name: opts[:name], ref: make_ref()}}
  end

  def notify_unregister(_), do: :ok

  def status(name, opts \\ []), do: Alfred.StatusAid.status(name, opts)
end
