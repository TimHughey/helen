defmodule Broom.TrackOpts do
  use Timex
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

      if is_iso_duration?(cfg_iso), do: cfg_iso, else: default
    end

    config_keys = [:track_timeout, :prune_interval, :prune_older_than]

    {%TrackOpts{
       track_timeout: first_valid.(:track_timeout),
       prune_interval: first_valid.(:prune_interval),
       prune_older_than: first_valid.(:prune_older_than)
     }, Keyword.drop(use_opts, config_keys)}
  end

  defp is_iso_duration?(arg) when is_binary(arg) do
    case Duration.parse(arg) do
      {:ok, _} -> true
      _error -> false
    end
  end

  defp is_iso_duration?(_not_binary), do: false

  # defp iso8601_duration_to_ms(binary) when is_binary(binary) do
  #   case Duration.parse(binary) do
  #     {:ok, x} -> Duration.to_milliseconds(x, truncate: true)
  #     {:error, msg} -> {:failed, msg}
  #   end
  # end
  #
  # defp iso8601_duration_to_ms(_what), do: nil
  #
  # defp iso8601_duration_to_ms(iso8601, default_ms)
  #      when is_binary(iso8601) and is_integer(default_ms) do
  #   case Duration.parse(iso8601) do
  #     {:ok, x} -> Duration.to_milliseconds(x, truncate: true)
  #     {:error, _msg} -> default_ms
  #   end
  # end
  #
  # defp iso8601_duration_to_ms(_, default_ms) when is_integer(default_ms), do: default_ms
end
