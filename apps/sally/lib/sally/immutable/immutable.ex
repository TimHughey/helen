defmodule Sally.Immutable do
  require Logger
  # require Ecto.Query

  alias __MODULE__
  alias Alfred.ImmutableStatus
  alias Sally.{Datapoint, DevAlias}

  @type ttl_ms() :: 50..600_000
  @type since_ms() :: pos_integer()
  @type opts() :: [ttl_ms: ttl_ms(), since_ms: since_ms()]

  @since_ms_default 1000 * 60 * 5
  @spec status(String.t(), Immutable.opts()) :: ImmutableStatus.t()
  def status(name, opts) when is_binary(name) and is_list(opts) do
    since_ms = opts[:since_ms] || @since_ms_default

    dev_alias = DevAlias.find(name) |> Datapoint.preload_avg(since_ms)

    cond do
      is_nil(dev_alias) -> ImmutableStatus.not_found(name)
      ttl_expired?(dev_alias, opts) -> ImmutableStatus.ttl_expired(dev_alias)
      good?(dev_alias) -> ImmutableStatus.good(dev_alias)
      :unmatched -> ImmutableStatus.unknown_status(dev_alias)
    end
    |> ImmutableStatus.finalize()
  end

  # (1 of 2) single map of data
  defp good?(%DevAlias{datapoints: [x]}) when is_map(x), do: true
  defp good?(_), do: false

  defp ttl_expired?(dev_alias, opts) do
    ttl_ms = opts[:ttl_ms] || dev_alias.ttl_ms
    ttl_start_at = DateTime.utc_now() |> DateTime.add(ttl_ms * -1, :millisecond)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    DateTime.compare(ttl_start_at, dev_alias.device.last_seen_at) == :gt or
      DateTime.compare(ttl_start_at, dev_alias.updated_at) == :gt
  end
end
