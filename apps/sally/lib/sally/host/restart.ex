defmodule Sally.Host.Restart do
  alias Sally.Host
  alias Sally.Host.Instruct

  def now(name) when is_binary(name) do
    case Host.find_by_name(name) do
      %Host{} = h -> now(h)
      nil -> {:not_found, name}
    end
  end

  def now(%Host{} = host) do
    Instruct.send(ident: host.ident, subsystem: "host", filters: ["restart"])
  end
end
