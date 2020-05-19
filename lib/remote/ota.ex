defmodule OTA do
  @moduledoc false

  require Logger

  alias TimeSupport

  alias Mqtt.Client

  @ota_https "ota.https"
  @restart_cmd "restart"

  def ota_uri(opts) when is_list(opts) do
    uri_opts = Keyword.take(opts, [:host, :path, :file])
    other_opts = Keyword.drop(opts, uri_opts)

    final_uri_opts = Keyword.merge(uri_default_opts(), uri_opts)

    actual_uri =
      [
        "https:/",
        Keyword.get(final_uri_opts, :host),
        Keyword.get(final_uri_opts, :path),
        Keyword.get(final_uri_opts, :file)
      ]
      |> Enum.join("/")

    [uri: actual_uri] ++ other_opts
  end

  def restart(false, opts) when is_list(opts), do: {:restart_bad_opts, opts}

  def restart(true, opts) when is_list(opts) do
    log = Keyword.get(opts, :log, true)

    # be sure to filter out any :not_found
    results =
      for %{host: host, name: name} <- Keyword.get(opts, :restart_list) do
        log && Logger.info(["send restart to: ", inspect(host, pretty: true)])

        legacy_cmd = %{
          cmd: @restart_cmd,
          mtime: TimeSupport.unix_now(:second),
          host: host,
          name: name,
          reboot_delay_ms: Keyword.get(opts, :reboot_delay_ms, 0)
        }

        # HACK
        #  temporarily publish command to host specific feed until
        #  all hosts have latest firmware
        Client.publish_to_host(legacy_cmd, "restart")

        {rc, _ref} = Client.publish_cmd(legacy_cmd)

        {name, host, rc}
      end

    log && Logger.info(["sent restart to: ", inspect(results, pretty: true)])
    results
  end

  def restart(opts) when is_list(opts) do
    restart(restart_opts_valid?(opts), opts)
  end

  def restart(anything) do
    Logger.warn(["restart bad args: ", inspect(anything, pretty: true)])
    {:bad_opts, anything}
  end

  def restart_opts_valid?(opts) do
    restart_list = Keyword.get(opts, :restart_list, [])

    cond do
      Enum.empty?(restart_list) -> false
      not is_map(hd(restart_list)) -> false
      true -> true
    end
  end

  def send_cmd(false, opts) when is_list(opts), do: {:send_bad_opts, opts}

  def send_cmd(true, opts) when is_list(opts) do
    log = Keyword.get(opts, :log, true)

    # be sure to filter out any :not_found
    results =
      for %{host: host, name: name} <- Keyword.get(opts, :update_list) do
        log && Logger.info(["send ota https to: ", inspect(host, pretty: true)])

        cmd = %{
          cmd: @ota_https,
          mtime: TimeSupport.unix_now(:second),
          host: host,
          name: name,
          # include :uri and deprecated :fw_url
          uri: Keyword.get(opts, :uri),
          fw_url: Keyword.get(opts, :uri),
          reboot_delay_ms: Keyword.get(opts, :reboot_delay_ms, 0)
        }

        # as of 2020-05-16 publish to the deprecated generic feed and
        # the host specific feed

        # DEPRECATED generic feed
        Client.publish_cmd(cmd)

        # NEW host specific feed
        {rc, _res} = Client.publish_to_host(cmd, "ota")

        {name, host, rc}
      end

    log && Logger.info(["sent ota https to: ", inspect(results, pretty: true)])

    results
  end

  def send_cmd(opts) when is_list(opts) do
    opts = ota_uri(opts)
    send_cmd(send_opts_valid?(opts), opts)
  end

  def send_cmd(anything) do
    Logger.warn(["send bad args: ", inspect(anything, pretty: true)])
    {:bad_opts, anything}
  end

  def send_opts_valid?(opts) do
    update_list = Keyword.get(opts, :update_list, [])

    cond do
      Enum.empty?(update_list) -> false
      not is_map(hd(update_list)) -> false
      true -> true
    end
  end

  defp uri_default_opts do
    Application.get_env(:helen, OTA,
      uri: [
        host: "localhost",
        path: "example_path",
        file: "example.bin"
      ]
    )
    |> Keyword.get(:uri)
  end
end
