defmodule Sally.PulseWidth.TestSupport do
  require Logger

  defstruct device_opts: [],
            device: nil,
            alias_opts: [],
            dev_alias: nil

  alias __MODULE__, as: TS

  alias Sally.PulseWidth.DB.{Alias, Device}

  def init(ctx) do
    device_opts = ctx[:device_opts] || ctx.defaults[:device_opts]
    alias_opts = ctx[:alias_opts] || []

    %TS{device_opts: device_opts, alias_opts: alias_opts}
    |> put_test_support_in_ctx(ctx)
  end

  def create_alias(%{ts: %TS{alias_opts: []}} = ctx), do: ctx

  def create_alias(%{ts: %TS{alias_opts: opts} = ts} = ctx) do
    case Alias.create(ts.device, opts) do
      {:ok, %Alias{} = x} -> %TS{ts | dev_alias: x}
      error -> log_error("failed to create alias", error, ts)
    end
    |> put_test_support_in_ctx(ctx)
  end

  def ensure_device(%{ts: %TS{device_opts: []}} = ctx), do: ctx

  def ensure_device(%{ts: %TS{device_opts: opts} = ts} = ctx) do
    dev_params = %{
      ident: opts[:ident],
      host: opts[:host],
      pios: opts[:pios] || 16,
      latency_us: :rand.uniform(1000) + 1000,
      last_seen_at: DateTime.utc_now()
    }

    %TS{ts | device: Device.upsert(dev_params)}
    |> put_test_support_in_ctx(ctx)
  end

  def delete_dev_aliases(pattern) do
    dev_aliases = Alias.names_begin_with(pattern)

    for dev_alias <- dev_aliases do
      Alias.delete(dev_alias)
    end
  end

  defp log_error(msg, error, ts) do
    Logger.warn("#{msg}: #{inspect(error, pretty: true)}")

    ts
  end

  defp put_test_support_in_ctx(%TS{} = ts, ctx), do: put_in(ctx, [:ts], ts)
end
