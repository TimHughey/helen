defmodule PulseWidth.Payload.Basic do
  @moduledoc false

  alias PulseWidth.DB.Device, as: Device

  def create_cmd(
        %Device{device: device, host: host},
        refid,
        %{name: _} = cmd,
        opts \\ []
      )
      when is_list(opts) and is_binary(refid) do
    %{
      pwm_cmd: 0x11,
      device: device,
      refid: refid,
      host: host,
      ack: Keyword.get(opts, :ack, true),
      cmd: Map.put(cmd, :type, "basic")
    }
  end

  @doc """
    Generate an example PulseWidth Random Sequence Payload
  """
  @doc since: "0.0.22"
  def example(%Device{} = pwm_dev) do
    alias Ecto.UUID

    cmd = %{
      name: "basic_random",
      activate: true,
      basic: %{
        repeat: false,
        steps:
          for _i <- 1..10 do
            %{duty: :rand.uniform(8191), ms: :rand.uniform(125)}
          end
      }
    }

    create_cmd(pwm_dev, UUID.generate(), cmd, [])
  end

  def send_cmd(
        %Device{device: device} = pwm,
        refid,
        %{} = cmd,
        opts \\ []
      )
      when is_binary(refid) do
    import Mqtt.Client, only: [publish_to_host: 3]
    # remove the keys from opts that are consumed by create_cmd
    pub_opts = Keyword.drop(opts, [:ack])

    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(pwm, refid, cmd, opts)
    |> publish_to_host(subtopic, pub_opts)
  end
end
