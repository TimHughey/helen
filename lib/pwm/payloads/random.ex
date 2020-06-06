defmodule PulseWidth.Payload.Random do
  @moduledoc """
    Creates the payload for a Random command to a Remote
  """

  require Logger

  def create_cmd(
        %PulseWidth{device: device, host: host},
        refid,
        %{name: _cmd_name} = cmd,
        opts
      )
      when is_list(opts) and is_binary(refid) do
    # def = %{name: "none", steps: [], run: false, repeat: false}

    %{
      pwm_cmd: 0x12,
      device: device,
      refid: refid,
      host: host,
      ack: Keyword.get(opts, :ack, true),
      cmd: Map.put(cmd, :type, "random")
    }
  end

  @doc """
    Generate an example PulseWidth Random Sequence Payload
  """
  @doc since: "0.0.22"
  def example(%PulseWidth{} = pwm_dev) do
    alias Ecto.UUID

    cmd = %{
      name: "cool",
      type: "random",
      activate: true,
      random: %{
        min: 0,
        max: 8191,
        primes: 10,
        step_ms: 75,
        step: 100,
        priority: 14
      }
    }

    create_cmd(pwm_dev, UUID.generate(), cmd, [])
  end

  def send_cmd(
        %PulseWidth{device: device} = pwm,
        refid,
        %{name: _cmd_name} = cmd,
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
