defmodule PulseWidth.Payload.Sequence do
  @moduledoc false

  require Logger

  def create_cmd(
        %PulseWidth{device: device, host: host},
        refid,
        %{name: _seq_name} = seq,
        opts
      )
      when is_list(opts) and is_binary(refid) do
    # def = %{name: "none", steps: [], run: false, repeat: false}

    %{
      seq_cmd: true,
      device: device,
      refid: refid,
      host: host,
      ack: Keyword.get(opts, :ack, true),
      seq: seq
    }
  end

  def send_cmd(
        %PulseWidth{device: device} = pwm,
        %PulseWidthCmd{refid: refid},
        %{name: _seq_name} = seq,
        opts \\ []
      ) do
    import Mqtt.Client, only: [publish_to_host: 3]
    # remove the keys from opts that are consumed by create_cmd
    pub_opts = Keyword.drop(opts, [:ack])

    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(pwm, refid, seq, opts)
    |> publish_to_host(subtopic, pub_opts)
  end
end
