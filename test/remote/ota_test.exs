defmodule OTATest do
  @moduledoc false

  use ExUnit.Case, async: true

  # import ExUnit.CaptureLog

  alias TimeSupport

  def preferred_vsn, do: "b4edefc"
  def host(num), do: "ruth.ota" <> Integer.to_string(num)
  def name(num), do: "ota" <> Integer.to_string(num)

  def ext(num),
    do: %{
      host: host(num),
      mtime: TimeSupport.unix_now(:second),
      log: false
    }

  setup_all do
    [log: false]
  end

  @moduletag :ota

  test "default url exists in environment" do
    ota_env = Application.get_env(:helen, OTA)

    assert is_list(ota_env)
    assert Keyword.has_key?(ota_env, :uri)
  end

  test "can create the default ota uri from config" do
    uri = OTA.ota_uri([])

    assert Keyword.has_key?(uri, :uri)
    assert Keyword.get(uri, :uri) |> String.contains?("https://")
    assert Keyword.get(uri, :uri) |> String.contains?("latest.bin")
  end

  test "send OTA with correct list format" do
    ext(0) |> Remote.external_update()
    hosts = [%{host: host(0), name: name(0)}]

    list = OTA.send_cmd(update_list: hosts, log: false)

    assert is_list(list)
    refute Enum.empty?(list)
    assert {_name, _host, :ok} = hd(list)
  end

  test "send OTA with incorrect list format" do
    ext(0) |> Remote.external_update()
    hosts = [host(0)]

    {rc, list} = OTA.send_cmd(update_hosts: hosts, log: false)

    assert is_list(list)
    refute Enum.empty?(list)
    assert rc == :send_bad_opts
  end
end
