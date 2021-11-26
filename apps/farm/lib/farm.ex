defmodule Farm do
  @moduledoc """
  Documentation for `Farm`.
  """

  alias Farm.Womb

  def womb_circulation_restart do
    Supervisor.terminate_child(Farm.Supervisor, Womb.Circulation)
    Supervisor.restart_child(Farm.Supervisor, Womb.Circulation)
  end

  def womb_heater_restart do
    Supervisor.terminate_child(Farm.Supervisor, Womb.Heater)
    Supervisor.restart_child(Farm.Supervisor, Womb.Heater)
  end

  def womb_circulation_state do
    :sys.get_state(Womb.Circulation)
  catch
    _, _ -> {:no_server, Womb.Circulation}
  end

  def womb_heater_state do
    :sys.get_state(Womb.Heater)
  catch
    _, _ -> {:no_server, Womb.Heater}
  end
end
