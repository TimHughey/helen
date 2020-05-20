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
      payload: "pwm",
      host: host,
      mtime: unix_now(:second),
      device: device,
      refid: refid,
      ack: Keyword.get(opts, :ack, true),
      duty: Keyword.get(opts, :duty, 0)
    }
  end

  def send_cmd(
        %PulseWidth{device: device} = pwm,
        %PulseWidthCmd{} = cmd,
        opts \\ []
      ) do
    # remove the keys from opts that are consumed by create_cmd
    pub_opts = Keyword.drop(opts, [:ack, :duty])

    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(pwm, cmd, opts)
    |> Mqtt.Client.publish_to_host(subtopic, pub_opts)
  end
end
