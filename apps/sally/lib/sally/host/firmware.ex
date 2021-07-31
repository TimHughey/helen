defmodule Sally.Host.Firmware do
  alias __MODULE__
  alias Sally.Host
  alias Sally.Host.Instruct

  @firmware_host Application.compile_env!(:sally, [Firmware, :uri, :host])
  @firmware_path Application.compile_env!(:sally, [Firmware, :uri, :path])

  def ota(name, firmware_file) when is_binary(name) do
    case Host.find_by_name(name) do
      %Host{} = host -> ota(host, firmware_file)
      nil -> {:not_found, name}
    end
  end

  def ota(%Host{} = h, file) do
    firmware_uri = [@firmware_path, file] |> Path.join()

    Instruct.send(
      ident: h.ident,
      subsystem: "host",
      data: %{uri: firmware_uri, src_host: @firmware_host},
      filters: ["ota"]
    )
  end
end
