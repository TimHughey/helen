defmodule Mqtt.SetProfile do
  @moduledoc false

  require Logger

  alias TimeSupport

  def create_cmd(%Remote{host: host, name: name, profile: profile}, _opts \\ []) do
    Map.merge(
      %{
        payload: "profile",
        mtime: TimeSupport.unix_now(:second),
        host: host,
        assigned_name: name
      },
      Remote.Profile.Schema.to_external_map(profile)
    )
  end

  def send_cmd(%Remote{} = r, opts \\ []) do
    # no opts consumed by create_cmd so pass them unchanged to publish_to_host
    create_cmd(r, opts) |> Mqtt.Client.publish_to_host("profile", opts)
  end
end
