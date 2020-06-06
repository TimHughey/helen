defmodule PulseWidth.Payload.Duty do
  @moduledoc false

  require Logger

  def create_cmd(
        %PulseWidth{device: device, host: host},
        refid,
        opts
      )
      when is_list(opts) and is_binary(refid) do
    %{
      pwm_cmd: 0x10,
      host: host,
      device: device,
      refid: refid,
      ack: Keyword.get(opts, :ack, true),
      duty: Keyword.get(opts, :duty, 0)
    }
  end

  @doc """
    Generate an example PulseWidth Duty Payload
  """
  @doc since: "0.0.22"
  def example(%PulseWidth{} = pwm_dev) do
    alias Ecto.UUID

    create_cmd(pwm_dev, UUID.generate(), duty: :rand.uniform(8191))
  end

  def send_cmd(
        %PulseWidth{device: device} = pwm,
        refid,
        opts \\ []
      )
      when is_binary(refid) do
    # remove the keys from opts that are consumed by create_cmd
    pub_opts = Keyword.drop(opts, [:ack, :duty])

    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(pwm, refid, opts)
    |> Mqtt.Client.publish_to_host(subtopic, pub_opts)
  end
end
