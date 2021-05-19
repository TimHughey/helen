defmodule Broom.Tracker do
  alias __MODULE__
  alias Broom.TrackerEntry, as: Entry

  defstruct refs: %{}, orphan_after_ms: 1000 * 15

  def init(orphan_after) when is_binary(orphan_after) do
    case EasyTime.iso8601_duration_to_ms(orphan_after) do
      {:ok, ms} -> %Tracker{orphan_after_ms: ms}
      _ -> %Tracker{}
    end
  end

  def get_refid_entry(refid, %Tracker{} = t) do
    get_in(t.refs, [refid])
  end

  def put_entry(%Entry{refid: refid} = te, %Tracker{} = t) do
    %Tracker{t | refs: put_in(t.refs, [refid], te)}
  end

  def remove_entry(%Entry{refid: refid}, %Tracker{} = t) do
    %Tracker{t | refs: Map.delete(t.refs, refid)}
  end
end
