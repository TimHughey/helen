defmodule Sally.Host.Firmware do
  alias Sally.Host
  alias Sally.Host.Instruct

  def ota(name, opts \\ []) when is_list(opts) do
    case Host.find_by_name(name) do
      %Host{} = host ->
        data = %{valid_ms: opts[:valid_ms] || 60_000, file: opts[:file] || "latest.bin"}

        Instruct.send(ident: host.ident, subsystem: "host", data: data, filters: ["ota"])

      nil ->
        {:not_found, name}
    end
  end
end
