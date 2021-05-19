defmodule Broom.TrackMsg do
  alias __MODULE__

  defstruct module: nil,
            schema: nil,
            orphan_after_ms: nil,
            notify_pid: nil,
            opts: [notify_when_released: false],
            server_pid: nil

  def create(module, schema, track_opts) do
    %TrackMsg{
      module: module,
      schema: schema,
      orphan_after_ms: track_opts[:orphan_after_ms],
      notify_pid: if(track_opts[:notify_when_released], do: self(), else: nil),
      opts: track_opts,
      server_pid: GenServer.whereis(module)
    }
  end

  def ensure_orphan_after_ms(%TrackMsg{} = tm, default_ms) when is_integer(default_ms) do
    # if orphan_after_ms is already set (by create/3 from a track opt) then keep it.
    # otherwise use the default value (provided by the caller)
    case tm do
      %TrackMsg{orphan_after_ms: nil} -> %TrackMsg{tm | orphan_after_ms: default_ms}
      _ -> tm
    end
  end
end
