defmodule Broom.Execute do
  @moduledoc false

  require Logger

  use Broom,
    schema: Broom.Command,
    track_timeout: "PT5S",
    prune_interval: "PT0.075S",
    prune_older_than: "PT0.1S",
    restart: :permanent,
    shutdown: 2000

  alias Broom.Repo
  alias Broom.TrackerEntry

  def track(this, opts), do: Broom.track(this, opts)

  @impl true
  def track_timeout(%TrackerEntry{schema_id: schema_id}) do
    Repo.transaction(fn ->
      # return the final cmd with associations loaded
      ack_or_orphan(schema_id) |> Repo.preload(dev_alias: [:device])
    end)
    |> elem(1)
  end

  def simulate_release_via_refid(refid) do
    Broom.get_refid_tracker_entry(refid) |> track_timeout() |> Broom.release()
  end

  # NOTE: simulate ack or orphan based on the cmd
  defp ack_or_orphan(cmd_schema_id) do
    cmd_schema = Repo.get!(Broom.Command, cmd_schema_id)

    # for the reference implementation we simulate acks and orphans using the cmd value
    disposition = String.to_atom(cmd_schema.cmd)

    # ack_now/2 returns the updated record, raises on failure
    Broom.Command.ack_now(cmd_schema, disposition, DateTime.utc_now())
  end
end
