defmodule Sally.Host.Dispatch do
  require Logger

  use Sally.Dispatch, subsystem: "host"

  @impl true
  # NOTE: current message categories: ["startup", "boot", "run"]
  def process(%Sally.Dispatch{} = msg) do
    {changes, replace_cols} = collect_changes(msg)
    changeset = Sally.Host.changeset(changes)
    insert_opts = Sally.Host.insert_opts(replace_cols)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:host, changeset, insert_opts)
    |> Sally.Repo.transaction()
  end

  @impl true
  def post_process(%Sally.Dispatch{category: "startup"} = msg) do
    [
      ident: msg.ident,
      name: msg.host.name,
      subsystem: "host",
      data: Sally.Host.boot_payload(msg.host),
      filters: ["profile", msg.host.name]
    ]
    |> Sally.Host.Instruct.send()
  end

  @impl true
  def post_process(%Sally.Dispatch{category: "boot"} = msg) do
    boot_profile = List.first(msg.filter_extra, "unknown")

    stack_size = msg.data[:stack]["size"] || 1
    stack_hw = msg.data[:stack]["highwater"] || 1
    stack_used = (100.0 - stack_hw / stack_size * 100.0) |> Float.round(2)

    [
      measurement: "host",
      tags: [ident: msg.host.ident, name: msg.host.name],
      fields: [
        boot_profile: boot_profile,
        boot_elapsed_ms: msg.data[:elapsed_ms] || 0,
        tasks: msg.data[:tasks] || 0,
        stack_size: stack_size,
        stack_high_water: stack_used,
        stack_used: stack_used
      ]
    ]
    |> Betty.metric()
  end

  @impl true
  def post_process(%Sally.Dispatch{category: "run"} = msg) do
    [
      measurement: "host",
      tags: [ident: msg.host.ident, name: msg.host.name],
      fields: [
        ap_primary_channel: msg.data[:ap]["pri_chan"] || 0,
        ap_rssi: msg.data[:ap]["rssi"] || 0,
        heap_min: msg.data.heap["min"],
        heap_max_alloc: msg.data.heap["max_alloc"],
        heap_free: msg.data.heap["free"]
      ]
    ]
    |> Betty.metric()
  end

  defp collect_changes(%{category: "startup"} = msg) do
    changes = %{
      ident: msg.ident,
      name: msg.ident,
      firmware_vsn: msg.data[:firmware_vsn],
      idf_vsn: msg.data[:idf_vsn],
      app_sha: msg.data[:app_sha],
      build_at: make_build_datetime(msg.data),
      start_at: msg.sent_at,
      seen_at: msg.sent_at,
      reset_reason: msg.data[:reset_reason]
    }

    {changes, Map.drop(changes, [:ident, :name]) |> Map.keys()}
  end

  defp collect_changes(%{category: cat} = msg) when cat in ["boot", "run"] do
    # NOTE: these are the columns to insert __OR__ update
    # {EDGE CASE] the host may be running and we don't have a database record
    # for it (missed the startup message)
    changes = %{ident: msg.ident, name: msg.ident, start_at: msg.sent_at, seen_at: msg.sent_at}

    # NOTE: we only want :seen_at updated however we must
    # include start_at to pass changeset validations on insert
    {changes, [:seen_at]}
  end

  @months ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  defp make_build_datetime(%{build_date: build_date, build_time: build_time}) do
    [month_bin, day, year] = String.split(build_date, " ", trim: true)
    month = Enum.find_index(@months, fn x -> x == month_bin end) + 1

    date = Date.new!(String.to_integer(year), month, String.to_integer(day))
    time = Time.from_iso8601!("#{build_time}.49152Z")

    DateTime.new!(date, time, "America/New_York")
  end

  defp make_build_datetime(_), do: nil
end
