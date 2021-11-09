defmodule Farm do
  @moduledoc """
  Documentation for `Farm`.
  """

  def womb(action) when is_atom(action) do
    alias Alfred.ExecCmd

    child_id = Farm.Womb
    ec = %ExecCmd{name: "womb heater power", cmd: "25% of max", type: "fixed", cmd_params: %{percent: 25}}

    case action do
      :circulation_on -> Alfred.execute(ec)
      :circulation_off -> Alfred.off()
      :restart -> Supervisor.restart_child(Farm.Supervisor, child_id)
      :state -> :sys.get_state(child_id)
      :terminate -> Supervisor.terminate_child(Farm.Supervisor, child_id)
      _ -> {:unknown_action, available_actions: [:circulation, :restart, :state, :terminate]}
    end
  end
end
