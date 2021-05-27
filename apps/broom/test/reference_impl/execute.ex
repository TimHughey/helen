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

  alias Broom.DB.{Alias, Command}
  alias Broom.TrackerEntry
  alias BroomRepo, as: Repo

  def track(this, opts), do: Broom.track(this, opts)

  @impl true
  def track_timeout(%TrackerEntry{schema_id: schema_id}) do
    Repo.transaction(fn ->
      cmd_final = ack_or_orphan(schema_id)

      # update the Alias to reflect the acked command
      if not cmd_final.orphaned, do: Alias.update_cmd(cmd_final.alias_id, cmd_final.cmd)

      # return the final cmd with associations loaded
      Repo.preload(cmd_final, alias: [:device])
    end)
    |> elem(1)
  end

  def simulate_release_via_refid(refid) do
    Broom.get_refid_tracker_entry(refid) |> track_timeout() |> Broom.release()
  end

  # NOTE: simulate ack or orphan based on the cmd
  defp ack_or_orphan(cmd_schema_id) do
    cmd_schema = Repo.get!(Command, cmd_schema_id)

    # for the reference implementation we simulate acks and orphans using the cmd value
    disposition = String.to_atom(cmd_schema.cmd)

    # ack_now/2 returns the updated record, raises on failure
    Command.ack_now(cmd_schema, disposition)
  end
end
