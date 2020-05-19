defmodule Mqtt.SetPulseWidth do
  @moduledoc false

  require Logger

  def create_cmd(
        %PulseWidth{device: device, host: host},
        %PulseWidthCmd{refid: refid},
        opts
      )
      when is_list(opts) do
    import TimeSupport, only: [unix_now: 1]

    %{
      cmd: "pwm",
      host: host,
      mtime: unix_now(:second),
      device: device,
      refid: refid,
      ack: Keyword.get(opts, :ack, true),
      duty: Keyword.get(opts, :duty, 0)
    }
  end
end
