defmodule Broom.Opts do
  alias Broom.Opts

  @orphan_after_default_ms 1000 * 15

  defstruct server: %{id: nil, name: nil, genserver: []},
            callback_mod: nil,
            schema: :missing,
            metrics: %{interval: "PT3M"},
            orphan: %{after: "PT15S"}

  def metrics_interval(%Opts{} = o), do: o.metrics.interval

  def make_opts(mod, %{} = o, use_opts) do
    {callback_mod, rest} = Keyword.pop(use_opts, :callback_mod, mod)
    {schema, rest} = Keyword.pop(rest, :schema, :missing)
    {id, rest} = Keyword.pop(rest, :id, mod)
    {name, genserver_opts} = Keyword.pop(rest, :name, mod)

    %Opts{
      server: %{id: id, name: name, genserver: genserver_opts},
      callback_mod: callback_mod,
      schema: schema,
      metrics: %{interval: determine_metrics_interval(o, %Opts{})},
      orphan: %{after: determine_orphan_after(o, %Opts{})}
    }
  end

  def orphan_after_ms(%Opts{orphan: %{after: after_iso}}) do
    case EasyTime.iso8601_duration_to_ms(after_iso) do
      x when is_integer(x) -> x
      _x -> @orphan_after_default_ms
    end
  end

  def update_metrics_interval(%Opts{} = o, new_interval) do
    %Opts{o | metrics: %{interval: new_interval}}
  end

  defp determine_metrics_interval(%Opts{} = o, default) do
    case o.metrics.interval do
      x when is_binary(x) -> x
      _ -> default.metrics.interval
    end
  end

  defp determine_orphan_after(%Opts{} = o, default) do
    case o.orphan.after do
      x when is_binary(x) -> x
      _ -> default.orphan.after
    end
  end
end
