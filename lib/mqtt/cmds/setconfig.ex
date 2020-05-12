defmodule Mqtt.SetConfig do
  @moduledoc false

  require Logger

  alias TimeSupport

  def send(%Remote{} = r), do: new_cmd(r) |> Mqtt.Client.publish_config()

  def new_cmd(%Remote{host: host, name: name, profile: profile}) do
    Map.merge(
      %{
        cmd: "config",
        mtime: TimeSupport.unix_now(:second),
        host: host,
        hostname: String.replace_prefix(name, "ruth.", "")
      },
      RemoteProfile.Schema.to_external_map(profile)
    )
  end
end
