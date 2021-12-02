defmodule Sally.Immutable do
  require Logger
  # require Ecto.Query

  alias __MODULE__
  alias Alfred.ImmutableStatus
  alias Sally.{Datapoint, DevAlias}
  # alias Sally.Repo

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
      good?(dev_alias) -> ImmutableStatus.good(dev_alias) |> add_tempf()
      :unmatched -> ImmutableStatus.unknown_status(dev_alias)
    end
    |> ImmutableStatus.finalize()
  end

  defp add_tempf(%ImmutableStatus{datapoints: %{temp_c: temp_c}} = status) do
    case temp_c do
      x when is_number(x) ->
        temp_f = (x * 9 / 5 + 32) |> Float.round(3)
        ImmutableStatus.add_datapoint(status, :temp_f, temp_f)

      _ ->
        status
    end
  end

  # (1 of 2) single datapount returned by Datapoint.query_preload_avg/1
  defp good?(%DevAlias{datapoints: [values_map]}) when is_map(values_map), do: true
  defp good?(_), do: false

  defp ttl_expired?(dev_alias, opts) do
    ttl_ms = opts[:ttl_ms] || dev_alias.ttl_ms
    ttl_start_at = DateTime.utc_now() |> DateTime.add(ttl_ms * -1, :millisecond)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    DateTime.compare(ttl_start_at, dev_alias.device.last_seen_at) == :gt or
      DateTime.compare(ttl_start_at, dev_alias.updated_at) == :gt
  end
end
