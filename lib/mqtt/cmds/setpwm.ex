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

    fade_opts =
      Keyword.take(opts, [
        :direction,
        :step_num,
        :duty_cycle_num,
        :duty_scale
      ])

    Map.merge(
      %{
        cmd: "pwm",
        host: host,
        mtime: unix_now(:second),
        device: device,
        refid: refid,
        ack: Keyword.get(opts, :ack, true),
        duty: Keyword.get(opts, :duty, 0)
      },
      Enum.into(fade_opts, %{})
    )
  end
end
