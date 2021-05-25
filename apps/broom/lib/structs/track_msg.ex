defmodule Broom.TrackMsg do
  alias __MODULE__

  defstruct module: nil,
            schema: nil,
            track_timeout_ms: nil,
            notify_pid: nil,
            opts: [notify_when_released: false],
            server_pid: nil

  def create(module, schema, track_opts) do
    %TrackMsg{
      module: module,
      schema: schema,
      track_timeout_ms: track_opts[:track_timeout_ms],
      notify_pid: if(track_opts[:notify_when_released], do: self(), else: nil),
      opts: track_opts,
      server_pid: GenServer.whereis(module)
    }
  end

  def ensure_track_timeout_ms(%TrackMsg{} = tm, default_ms) when is_integer(default_ms) do
    # if track_timeout_ms is already set (by create/3 from a track opt) then keep it.
    # otherwise use the default value (provided by the caller)
    case tm do
      %TrackMsg{track_timeout_ms: nil} -> %TrackMsg{tm | track_timeout_ms: default_ms}
      _ -> tm
    end
  end
end
