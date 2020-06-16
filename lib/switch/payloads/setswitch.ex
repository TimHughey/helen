defmodule Switch.Payload.Position do
  @moduledoc false

  require Logger

  alias TimeSupport

  alias Switch.DB.Device, as: Device
  alias Switch.DB.Command, as: Command

  def create_cmd(
        %Device{device: device, host: host},
        %Command{refid: refid},
        %{pio: _pio, state: _state} = state_map,
        opts \\ []
      )
      when is_list(opts) do
    import TimeSupport, only: [unix_now: 1]

    %{
      payload: "switch state",
      mtime: unix_now(:second),
      host: host,
      device: device,
      states: [state_map],
      refid: refid,
      ack: Keyword.get(opts, :ack, true)
    }
  end

  def send_cmd(
        %Device{device: device} = d,
        %Command{} = c,
        state_map,
        opts \\ []
      )
      when is_map(state_map) do
    # remove the keys from opts that are consumed by create_cmd
    pub_opts = Keyword.drop(opts, [:ack])

    # extract the prefix of the device and use it as the subtopic
    subtopic = String.split(device, "/") |> hd()

    create_cmd(d, c, state_map, opts)
    |> Mqtt.Client.publish_to_host(subtopic, pub_opts)
  end
end
