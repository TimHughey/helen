defmodule PulseWidth.Payload.Basic do
  @moduledoc false

  require Logger

  def create_cmd(
        %PulseWidth{device: device, host: host},
        refid,
        %{name: name, repeat: _, steps: _} = cmd,
        opts
      )
      when is_list(opts) and is_binary(refid) do
    cmd = %{
      type: "basic",
      name: name,
      # activate if not specified
      activate: Map.get(cmd, :activate, true),
      # take the two components of the basic command and store them in a
      # key == type so the Remote can directly get to the details
      basic: Map.take(cmd, [:repeat, :steps])
    }

    %{
      pwm_cmd: 0x11,
      device: device,
      refid: refid,
      host: host,
      ack: Keyword.get(opts, :ack, true),
      cmd: cmd
    }
  end

  @doc """
    Generate an example PulseWidth Random Sequence Payload
  """
  @doc since: "0.0.22"
  def example(%PulseWidth{} = pwm_dev) do
    alias Ecto.UUID

    cmd = %{
      name: "basic_random",
      repeat: true,
      steps:
        for _i <- 1..10 do
          %{duty: :rand.uniform(8191), ms: :rand.uniform(125)}
        end
    }

    create_cmd(pwm_dev, UUID.generate(), cmd, [])
  end

  def send_cmd(
        %PulseWidth{device: device} = pwm,
        refid,
        %{name: _cmd_name, repeat: _, steps: _} = cmd,
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
