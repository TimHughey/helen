defmodule Sally.Host.Firmware do
  alias Sally.Host
  alias Sally.Host.Instruct

  def ota(what, opts \\ [])

  def ota(:live, opts) when is_list(opts) do
    for %Host{} = host <- Host.live(opts) do
      host |> ota(opts)
    end
  end

  def ota(name, opts) when is_binary(name) and is_list(opts) do
    case Host.find_by(name: name) do
      %Host{} = host -> ota(host, opts)
      nil -> {:not_found, name}
    end
  end

  def ota(%Host{} = host, opts) when is_list(opts) do
    {valid_ms, opts_rest} = Keyword.pop(opts, :valid_ms, 60_000)
    {fw_file, _opts_rest} = Keyword.pop(opts_rest, :file, "latest.bin")

    [ident: host.ident, filters: ["ota"], data: %{valid_ms: valid_ms, file: fw_file}]
    |> Instruct.send()
  end
end
