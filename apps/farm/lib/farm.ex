defmodule Farm do
  @moduledoc """
  Documentation for `Farm`.
  """

  def womb(action) when is_atom(action) do
    child_id = Farm.Womb
    circulation = "womb heater power"

    case action do
      :circulation -> Alfred.toggle(circulation)
      :restart -> Supervisor.restart_child(Farm.Supervisor, child_id)
      :state -> :sys.get_state(child_id)
      :terminate -> Supervisor.terminate_child(Farm.Supervisor, child_id)
      _ -> {:unknown_action, available_actions: [:restart, :state, :terminate]}
    end
  end
end
