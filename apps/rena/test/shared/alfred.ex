defmodule Rena.Alfred do
  use Alfred.StatusAid
  use Alfred.ExecAid
  alias Alfred.Notify.Ticket

  def notify_register(opts) do
    {:ok, %Ticket{name: opts[:name], ref: make_ref()}}
  end

  def notify_unregister(_), do: :ok
end
