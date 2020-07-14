defmodule PulseWidth.Payload.Basic do
  @moduledoc false

  alias PulseWidth.DB.Device, as: Device

  def create_cmd(%_{device: d, host: h, cmds: [%_{refid: ref}]}, cmd_map, opts)
      when is_list(opts) do
    %{
      pwm_cmd: 0x12,
      device: d,
      refid: ref,
      host: h,
      ack: opts[:ack] || true,
      cmd: Map.put(cmd_map, :type, "basic")
    }
  end

  @doc """
    Generate an example PulseWidth Random Sequence Payload
  """
  @doc since: "0.0.22"
  def example(%Device{} = pwm_dev) do
    cmd = %{
      name: "basic_random",
      basic: %{
        repeat: false,
        steps:
          for _i <- 1..10 do
            %{duty: :rand.uniform(8191), ms: :rand.uniform(125)}
          end
      }
    }

    create_cmd(pwm_dev, cmd, [])
  end

  def send_cmd(%Device{device: device} = pwm, %{} = cmd_map, opts \\ []) do
    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(pwm, cmd_map, opts)
    |> Mqtt.Client.publish_to_host(subtopic, opts)
  end
end
