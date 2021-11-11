defmodule Farm do
  @moduledoc """
  Documentation for `Farm`.
  """

  def womb(action) when is_atom(action) do
    alias Alfred.ExecCmd

    child_id = Farm.Womb
    circulation = "womb circulation pwm"
    ec = %ExecCmd{name: circulation, cmd: "25% of max", cmd_params: %{type: "fixed", percent: 25}}

    available_actions = [:circulation_on, :circulation_off, :restart, :state, :terminate]

    case action do
      :circulation_on -> Alfred.execute(ec)
      :circulation_off -> Alfred.off(circulation)
      :restart -> Supervisor.restart_child(Farm.Supervisor, child_id)
      :state -> :sys.get_state(child_id)
      :terminate -> Supervisor.terminate_child(Farm.Supervisor, child_id)
      _ -> {:unknown_action, available_actions: available_actions}
    end
  end
end
