defmodule Broom.MetricsOpts do
  alias __MODULE__

  defstruct interval: "PT5M"

  @type iso8601_duration :: String.t()
  @type t :: %__MODULE__{interval: iso8601_duration()}

  def is_valid?(%MetricsOpts{} = metrics_opts) do
    EasyTime.is_iso_duration?(metrics_opts.interval)
  end

  def make(start_opts, use_opts) do
    first_valid = fn key ->
      default = %MetricsOpts{} |> Map.get(key)

      start_opts[key] || use_opts[key] || default
    end

    config_keys = [:metrics_interval]

    {%MetricsOpts{interval: first_valid.(:metrics_interval)}, Keyword.drop(use_opts, config_keys)}
  end

  def update(%MetricsOpts{} = m, opts) do
    new_opts = %MetricsOpts{m | interval: opts[:metrics_interval]}

    if is_valid?(new_opts), do: {:ok, new_opts}, else: {:failed, "invalid opts: #{inspect(new_opts)}"}
  end
end
