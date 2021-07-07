defmodule Sally.Mutable do
  require Logger
  require Ecto.Query

  alias Alfred.MutableStatus
  alias Sally.{Command, DevAlias}
  alias Sally.Repo

  @type ttl_ms() :: 50..600_000
  @type opts() :: [ttl_ms: ttl_ms(), need_dev_alias: boolean()]

  @spec status(Sring.t(), Status.opts()) :: MutableStatus.t()
  def status(name, opts) when is_binary(name) and is_list(opts) do
    alias Ecto.Query

    last_cmd_query = Query.from(c in Command, order_by: [desc: c.sent_at], limit: 1)
    dev_alias = Repo.get_by(DevAlias, name: name) |> Repo.preload(cmds: last_cmd_query, device: [])

    Logger.debug(["\n", inspect(dev_alias, pretty: true)])

    cond do
      is_nil(dev_alias) -> MutableStatus.not_found(name)
      ttl_expired?(dev_alias, opts) -> MutableStatus.ttl_expired(dev_alias)
      pending?(dev_alias) -> MutableStatus.pending(dev_alias)
      orphaned?(dev_alias) -> MutableStatus.unresponsive(dev_alias)
      good?(dev_alias) -> MutableStatus.good(dev_alias)
      :unmatched -> MutableStatus.unknown_state(dev_alias)
    end
    |> make_response(dev_alias, opts)
  end

  # when there is not a last Command there isn't a current command for the status.
  # to ensure there is a proper status an acked command is inserted to represent
  # the current cmd while processing messages from the remote host.

  defp good?(%DevAlias{cmds: []}), do: false
  defp good?(%DevAlias{cmds: [%Command{acked: true}]}), do: true

  defp make_response(res, dev_alias, opts) do
    if opts[:need_dev_alias], do: {dev_alias, res}, else: res
  end

  # (1 of 2) possible orphan
  defp orphaned?(%DevAlias{cmds: [%Command{orphaned: true, acked_at: acked_at}]} = dev_alias) do
    DateTime.compare(dev_alias.updated_at, acked_at) == :lt
  end

  # (2 of 2) never an orphan
  defp orphaned?(_dev_alias), do: false

  defp pending?(dev_alias) do
    case dev_alias do
      %DevAlias{cmds: [%Command{acked: false}]} -> true
      _ -> false
    end
  end

  defp ttl_expired?(dev_alias, opts) do
    ttl_ms = opts[:ttl_ms] || dev_alias.ttl_ms
    ttl_start_at = DateTime.utc_now() |> DateTime.add(ttl_ms * -1, :millisecond)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    DateTime.compare(ttl_start_at, dev_alias.device.last_seen_at) == :gt or
      DateTime.compare(ttl_start_at, dev_alias.updated_at) == :gt
  end
end
