defmodule RuthSim.InboundMsg do
  alias RuthSim.InboundMsg.Server

  @dev_type_to_mod %{"pwm" => PwmSim.ExecCmd, "switch" => SwitchSim.ExecCmd}

  def process({:ok, unpacked}, dev_type) do
    Server.cast({:process_msg, @dev_type_to_mod[dev_type], unpacked})
  end

  def process({:error, _unpack_error}, _dev_type) do
    nil
  end
end
