defmodule Broom.Opts do
  require Logger

  alias Broom.Opts
  alias Broom.{MetricsOpts, TrackOpts}
  alias Broom.TypesBase, as: Types

  defstruct server: %{id: nil, name: nil, genserver: []},
            callback_mod: nil,
            schema: :missing,
            metrics: %{interval: "PT3M"},
            track: %TrackOpts{}

  @type t :: %__MODULE__{
          server: Types.server_info_map(),
          callback_mod: Types.module_or_nil(),
          schema: Types.schema_or_nil(),
          metrics: Types.metrics_opts(),
          track: Types.track_opts()
        }

  def make_opts(mod, start_opts, use_opts) do
    {callback_mod, rest} = Keyword.pop(use_opts, :callback_mod, mod)
    {schema, rest} = Keyword.pop(rest, :schema, :missing)
    {id, rest} = Keyword.pop(rest, :id, mod)
    {track_opts, rest} = TrackOpts.make(start_opts, rest)
    {metrics_opts, rest} = MetricsOpts.make(start_opts, rest)
    {name, genserver_opts} = Keyword.pop(rest, :name, mod)

    %Opts{
      server: %{id: id, name: name, genserver: genserver_opts},
      callback_mod: callback_mod,
      schema: schema,
      metrics: metrics_opts,
      track: track_opts
    }
    |> log_final_opts()
  end

  def metrics(%Opts{metrics: metrics_opts}), do: metrics_opts

  def update_metrics(%Opts{} = o, opts) do
    case MetricsOpts.update(o.metrics, opts) do
      {:ok, %MetricsOpts{} = metrics_opts} -> {:ok, %Opts{o | metrics: metrics_opts}}
      {:failed, _msg} = rc -> rc
    end
  end

  defp log_final_opts(%Opts{} = o) do
    Logger.debug(["final opts:\n", inspect(o, pretty: true)])
    o
  end
end
