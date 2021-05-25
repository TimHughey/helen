defmodule Broom.Tracker do
  require Logger

  alias __MODULE__

  alias Broom.BaseTypes, as: Types
  alias Broom.TrackerEntry, as: Entry
  alias Broom.TrackOpts

  # NOTE:  the most recently released refid is always at the start of the list
  defstruct refs: %{},
            released: [],
            track_timeout_ms: nil,
            prune_interval_ms: nil,
            prune_older_than_ms: nil,
            prune_timer: nil

  @type tracked_refs() :: %{required(Types.refid()) => Entry.t(refid: Types.refid())}
  @type t :: %__MODULE__{
          refs: tracked_refs(),
          released: [String.t(), ...],
          track_timeout_ms: pos_integer,
          prune_interval_ms: pos_integer,
          prune_older_than_ms: pos_integer,
          prune_timer: reference()
        }

  def apply_opts(%Tracker{} = t, %TrackOpts{} = track_opts) do
    to_ms = fn key -> Map.get(track_opts, key) |> EasyTime.iso8601_duration_to_ms() end

    %Tracker{
      t
      | track_timeout_ms: to_ms.(:track_timeout),
        prune_interval_ms: to_ms.(:prune_interval),
        prune_older_than_ms: to_ms.(:prune_older_than)
    }
  end

  def init(%TrackOpts{} = track_opts), do: %Tracker{} |> apply_opts(track_opts) |> schedule_prune()

  def get_refid_entry(refid, %Tracker{} = t) do
    get_in(t.refs, [refid])
  end

  def put_entry(%Entry{refid: refid} = te, %Tracker{} = t) do
    %Tracker{t | refs: put_in(t.refs, [refid], te)}
  end

  def release_entry(%Entry{refid: refid} = te, %Tracker{} = t) do
    refs = put_in(t.refs, [refid], te)
    released = [refid | t.released] |> List.flatten()

    %Tracker{t | refs: refs, released: released}
  end

  def prune_refs(%Tracker{released: []} = t), do: t |> schedule_prune()

  def prune_refs(%Tracker{} = t) do
    old_at = DateTime.utc_now() |> DateTime.add(t.prune_older_than_ms * -1, :millisecond)

    {prune_refs, keep_refs} =
      Enum.split_with(t.released, fn refid -> Map.get(t.refs, refid) |> Entry.older_than?(old_at) end)

    Logger.debug("will release #{length(prune_refs)} of #{length(keep_refs)} refs")

    %Tracker{t | refs: Map.drop(t.refs, prune_refs), released: keep_refs}
    |> schedule_prune()
  end

  defp schedule_prune(%Tracker{} = t) do
    %Tracker{t | prune_timer: Process.send_after(self(), :prune_refs, t.prune_interval_ms)}
  end
end
