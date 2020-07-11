defmodule PulseWidth.Payload.Duty do
  @moduledoc false

  alias PulseWidth.DB.Device, as: Device

  def create_cmd(%_{device: d, host: h, cmds: [%_{refid: ref}]}, cmd_map, opts)
      when is_list(opts) do
    %{
      pwm_cmd: 0x10,
      host: h,
      device: d,
      refid: ref,
      ack: opts[:ack] || true,
      duty: cmd_map[:duty] || 0
    }
  end

  @doc """
    Generate an example PulseWidth Duty Payload
  """
  @doc since: "0.0.22"
  def example(%{} = pwm_dev) do
    create_cmd(pwm_dev, %{duty: :rand.uniform(8191)}, [])
  end

  def send_cmd(%Device{device: device} = pwm, %{} = cmd_map, opts \\ []) do
    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(pwm, cmd_map, opts)
    |> Mqtt.Client.publish_to_host(subtopic, opts)
  end
end
