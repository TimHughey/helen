defmodule PulseWidth.Payload.Auto do
  @moduledoc """
  Creates the appropriate PulseWidth command automatically based on the
  contents of the command map.
  """

  alias PulseWidth.DB.Device, as: Device
  alias PulseWidth.Payload.{Basic, Duty, Random}

  @doc """
  Routes the command to appriopriate Payload module based on the command
  map contents.  In other words, provides a single point of invocation for
  PulesWidth.DB.Command.
  """
  @doc since: "0.0.27"
  def send_cmd(%Device{} = pwm, cmd_map, opts \\ []) do
    case cmd_map do
      # allow a flat map that includes the type.  translate the flat map
      # into a command map.
      %{type: type} -> send_cmd(pwm, %{type => Map.drop(cmd_map, [:type])})
      %{duty: _} -> Duty.send_cmd(pwm, cmd_map, opts)
      %{random: %{max: _, min: _}} -> Random.send_cmd(pwm, cmd_map, opts)
      %{basic: %{steps: _}} -> Basic.send_cmd(pwm, cmd_map, opts)
    end
  end
end
