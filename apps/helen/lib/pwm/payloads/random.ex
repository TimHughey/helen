defmodule PulseWidth.Payload.Random do
  @moduledoc """
    Creates the payload for a Random command to a Remote
  """

  alias PulseWidth.DB.Device, as: Device

  def create_cmd(%_{device: d, host: h, cmds: [%_{refid: ref}]}, cmd_map, opts)
      when is_list(opts) do
    %{
      pwm_cmd: 0x12,
      device: d,
      refid: ref,
      host: h,
      ack: opts[:ack] || true,
      cmd: Map.put(cmd_map, :type, "random")
    }
  end

  @doc """
    Generate an example PulseWidth Random Sequence Payload
  """
  @doc since: "0.0.22"
  def example(%Device{} = pwm_dev) do
    cmd = %{
      name: "random fade",
      type: "random",
      random: %{
        min: 256,
        max: 2048,
        primes: 25,
        step_ms: 50,
        step: 7,
        priority: 7
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
