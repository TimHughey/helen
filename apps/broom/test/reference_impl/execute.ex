defmodule Broom.Execute do
  @moduledoc false

  require Logger

  use Broom,
    schema: Broom.DB.Command,
    track_timeout: "PT5S",
    prune_interval: "PT0.075S",
    prune_older_than: "PT0.1S",
    restart: :permanent,
    shutdown: 2000

  alias Broom.DB.Command
  alias Broom.TrackerEntry

  def track(this, opts), do: Broom.track(this, opts)

  @impl true
  def track_timeout(%TrackerEntry{schema_id: schema_id}) do
    BroomRepo.transaction(fn ->
      BroomRepo.get(Command, schema_id) |> Command.load_alias() |> ack_or_orphan()
    end)
    |> elem(1)
  end

  def simulate_release_via_refid(refid) do
    Broom.get_refid_tracker_entry(refid) |> track_timeout() |> Broom.release()
  end

  # NOTE: simulate ack or orphan based on the cmd
  defp ack_or_orphan(%Command{} = c) do
    case c do
      %Command{cmd: "orphan"} -> Command.orphan_now(c.id)
      %Command{cmd: "ack"} -> Command.ack_now(c.id, DateTime.utc_now())
    end
  end
end
