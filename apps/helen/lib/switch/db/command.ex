defmodule Switch.DB.Command do
  @moduledoc false

  use Ecto.Schema
  use BroomOld
  use Timex

  alias Switch.Command.Fact
  alias Switch.DB.Command, as: Schema
  alias Switch.DB.{Alias, Device}

  schema "switch_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:alias_id, :id)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphan, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:ack_at, :utc_datetime_usec)

    belongs_to(:alias, Alias,
      source: :alias_id,
      references: :id,
      foreign_key: :alias_id,
      define_field: false
    )

    timestamps(type: :utc_datetime_usec)
  end

  def acked?(refid) do
    cmd = find_refid(refid)

    if is_nil(cmd), do: false, else: cmd.acked
  end

  # NOTE:
  # original msg is augmented with ack results and returned for downstream processing
  def ack_if_needed(%{cmdack: true, refid: refid, msg_recv_dt: recv_dt, device: {:ok, %Device{}}} = msg) do
    put_cmd_rc = fn x -> Map.drop(msg, [:cmdack, :refid]) |> put_in([:cmd_rc], x) end

    base_opts = [acked: true, ack_at: Timex.now()]

    case find_refid(refid) do
      %Schema{sent_at: sent_at} = cmd_to_ack ->
        cmd_to_ack
        |> update(base_opts ++ [rt_latency_us: Timex.diff(recv_dt, sent_at, :microsecond)])
        |> put_cmd_rc.()
        |> Fact.write_metric()

      {:error, e} ->
        put_cmd_rc.({:failed, "unable to find refid: #{inspect(e)}"})

      # allow receipt of refid ack messages while passively processing the rpt topic
      # (e.g. testing by attaching to production reporting topic)
      nil ->
        put_cmd_rc.({:ok, "unknown refid: #{refid}"})
    end
  end

  def ack_if_needed(msg), do: put_in(msg, [:cmd_rc], {:ok, "ignored, not a cmdack"})

  def add(%Alias{} = a, %{cmd: cmd}, opts) do
    # associate the new command with the Alias
    new_cmd = Ecto.build_assoc(a, :cmds)

    base_cs = [sent_at: Timex.now(), cmd: cmd]

    if opts[:ack] == :immediate do
      acked_cs = [acked: true, orphan: false, rt_latency_us: 0, ack_at: Timex.now()]
      changeset(new_cmd, base_cs ++ acked_cs) |> insert_and_track(opts)
    else
      changeset(new_cmd, base_cs) |> insert_and_track(opts)
    end
  end

  # (1 of 2) insure changes are a map
  def changeset(%Schema{} = c, changes) when is_list(changes) do
    changeset(c, Enum.into(changes, %{}))
  end

  def changeset(%Schema{} = c, changes) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:cmd, :sent_at, :alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.unique_constraint(:refid)
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)

  # BroomOld default opts
  def default_opts,
    do: [
      orphan: [startup_check: true, sent_before: "PT12S", older_than: "PT1M"],
      purge: [at_startup: true, interval: "PT2M", older_than: "PT7D"],
      metrics: "PT1M"
    ]

  def put_status(m, status), do: put_in(m, [:cmd_last], status)

  # (1 of 5) received an empty list
  def status(m, []), do: put_status(m, %{cmd: "unknown"})

  # ( 1 of 5) received a list of cmds grab the first one
  def status(m, cmds) when is_list(cmds), do: status(m, hd(cmds))

  # (2 of 5) acked cmd
  def status(m, %Schema{acked: true, orphan: false} = c) when is_map(m) do
    put_status(m, %{cmd: c.cmd, acked: true, ack_at: c.ack_at, rt_latency_us: c.rt_latency_us})
  end

  # (3 of 5) pending
  def status(m, %Schema{acked: false} = c) when is_map(m) do
    put_status(m, %{cmd: c.cmd, pending: true, at: c.ack_at, refid: c.refid})
  end

  # (4 of 5) orphan
  def status(m, %Schema{orphan: true} = c) do
    put_status(m, %{cmd: "unknown", orphan: true, orphan_at: c.ack_at})
  end

  # (5 of 5)
  def status(m, _) do
    put_status(m, %{cmd: "unknown", invalid: true, at: Timex.now()})
  end

  def update(refid, opts) when is_binary(refid) and is_list(opts) do
    changes = Keyword.take(opts, columns(:update))

    case find_refid(refid) do
      %Schema{} = c -> changeset(c, changes) |> update()
      _ -> {:not_found, refid}
    end
  end

  def update(%Schema{} = c, changes) do
    changeset(c, changes) |> update()
  end

  def update(%Ecto.Changeset{} = cs) do
    case cs do
      %{valid?: true} -> {:ok, Repo.update!(cs, returning: true) |> Repo.preload([:alias])}
      cs -> {:invalid_changes, cs}
    end
  end
end
