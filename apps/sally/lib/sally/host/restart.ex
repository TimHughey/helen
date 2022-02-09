defmodule Sally.Host.Restart do
  alias Sally.Host
  alias Sally.Host.Instruct

  def now(name, opts) when is_binary(name) and is_list(opts) do
    case Host.find_by_name(name) do
      %Host{} = h -> now(h, opts)
      nil -> {:not_found, name}
    end
  end

  @doc false
  def now(%Host{} = host, opts) when is_list(opts) do
    instruct = opts[:instruct] || Instruct

    instruct.send(ident: host.ident, subsystem: "host", filters: ["restart"])
  end
end
