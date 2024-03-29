defmodule Farm do
  @moduledoc """
  Documentation for `Farm`.
  """

  use Carol, otp_app: :farm

  alias Farm.Womb

  def womb_heater_restart do
    Supervisor.terminate_child(Farm.Supervisor, Farm.Womb.Heater)
    Supervisor.restart_child(Farm.Supervisor, Farm.Womb.Heater)
  end

  def womb_heater_state do
    :sys.get_state(Womb.Heater)
  catch
    _, _ -> {:no_server, Womb.Heater}
  end
end
