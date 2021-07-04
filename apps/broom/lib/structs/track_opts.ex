defmodule Broom.TrackOpts do
  alias __MODULE__

  defstruct track_timeout: "PT3.3S", prune_interval: "PT1M", prune_older_than: "PT24H"

  @type iso8601_duration :: String.t()
  @type t :: %__MODULE__{
          track_timeout: iso8601_duration(),
          prune_interval: iso8601_duration(),
          prune_older_than: iso8601_duration()
        }

  def make(start_opts, use_opts) do
    first_valid = fn key ->
      default = %TrackOpts{} |> Map.get(key)

      cfg_iso = start_opts[key] || use_opts[key]

      if EasyTime.is_iso_duration?(cfg_iso), do: cfg_iso, else: default
    end

    config_keys = [:track_timeout, :prune_interval, :prune_older_than]

    {%TrackOpts{
       track_timeout: first_valid.(:track_timeout),
       prune_interval: first_valid.(:prune_interval),
       prune_older_than: first_valid.(:prune_older_than)
     }, Keyword.drop(use_opts, config_keys)}
  end
end
