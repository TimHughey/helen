defmodule Switch.DB.Command do
  @moduledoc """
  Database functionality for Switch Command
  """

  use Ecto.Schema
  use Broom

  alias Switch.DB.{Alias, Device}
  alias Switch.DB.Command, as: Schema

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
  def ack(%{cmdack: true, refid: refid, msg_recv_dt: recv_dt, device: {:ok, %Device{}}} = msg) do
    import Switch.Command.Fact, only: [write_metric: 1]
    import Helen.Time.Helper, only: [utc_now: 0]

    base_opts = [acked: true, ack_at: utc_now()]

    case find_refid(refid) do
      %Schema{sent_at: sent_at} = cmd_to_ack ->
        latency_us = Timex.diff(recv_dt, sent_at, :microsecond)
        update_rc = update(cmd_to_ack, base_opts ++ [rt_latency_us: latency_us])

        put_in(msg, [:cmd_rc], update_rc)
        |> write_metric()

      {:error, e} ->
        put_in(msg, [:cmd_rc], {:failed, "unable to find refid: #{inspect(e)}"})

      # allow receipt of refid ack messages while passively processing the rpt topic
      # (e.g. testing by attaching to production rpt topic)
      nil ->
        put_in(msg, [:cmd_rc], {:unknown, "unknown refid: #{refid}"})
    end
  end

  # NOTE:
  # all active_cmd/1 functions assume the received Command structs are
  # ordered descending and will always use the head of the list

  # (1 of 4) nominal case, we received a list of commands
  def active_cmd(cmds) when is_list(cmds) and cmds != [], do: active_cmd(hd(cmds))

  # (2 of 4) nominal case, acked cmd and not an orphan
  def active_cmd(%Schema{cmd: cmd, acked: true, orphan: false}) do
    map_cmd(cmd)
  end

  # (3 of 4) there's an unacked cmd, flag this is pending
  def active_cmd(%Schema{cmd: cmd, acked: false, refid: refid}),
    do: {:pending, map_cmd(cmd), refid}

  # (4 of 4) there aren't any commands yet, assume the device is off
  def active_cmd([]), do: :off

  # (5 of 5) there could be an orphan or an error, either way the cmd is unknown
  def active_cmd(_), do: :unknown

  def add(%Alias{} = a, %{cmd: cmd}, opts) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # associate the new command with the Alias
    new_cmd = Ecto.build_assoc(a, :cmds)

    base_cs = [sent_at: utc_now(), cmd: cmd]

    if opts[:ack] == :immediate do
      acked_cs = [acked: true, orphan: false, rt_latency_us: 0, ack_at: utc_now()]
      changeset(new_cmd, base_cs ++ acked_cs) |> insert_and_track(opts)
    else
      changeset(new_cmd, base_cs) |> insert_and_track(opts)
    end
  end

  # (1 of 3) convert a params list to a map
  def changeset(%Schema{} = c, p) when is_list(p), do: changeset(c, Enum.into(p, %{}))

  # (2 of 3) if cmd is an atom make it a binary
  def changeset(%Schema{} = c, %{cmd: cmd} = p) when is_atom(cmd) do
    changeset(c, put_in(p.cmd, Atom.to_string(cmd)))
  end

  # (3 of 3) params are a map and :cmd is a binary
  def changeset(%Schema{} = c, p) when is_map(p) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(p, columns(:all))
    |> Changeset.validate_required([:cmd, :sent_at, :alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.unique_constraint(:refid)
  end

  # helpers for changeset columns
  def columns(:all) do
    import List, only: [flatten: 1]
    import Map, only: [drop: 2, from_struct: 1, keys: 1]

    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> flatten()

    %Schema{} |> from_struct() |> drop(these_cols) |> keys() |> flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:cmd, :sent_at, :alias_id])
  def columns(:update), do: columns_all(drop: [:alias_id])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  # Broom default opts
  def default_opts,
    do: [
      orphan: [startup_check: true, sent_before: "PT12S", older_than: "PT1M"],
      purge: [at_startup: true, interval: "PT2M", older_than: "PT7D"],
      metrics: "PT1M"
    ]

  def map_cmd(cmd) do
    import String, only: [to_atom: 1]
    # 1. defined cmds are converted to atoms
    # 2. custom cmds are left binary

    case cmd do
      cmd when cmd in ["on", "off", "unknown"] -> to_atom(cmd)
      cmd when cmd in [:on, :off, :unknown] -> to_string(cmd)
    end
  end

  def put_status(m, status), do: put_in(m, [:local_cmd], status)

  # (1 of 5) received an empty list
  def status(m, []), do: put_status(m, %{cmd: :unknown})

  # ( 1 of 5) received a list of cmds grab the first one
  def status(m, cmds) when is_list(cmds), do: status(m, hd(cmds))

  # (2 of 5) acked cmd
  def status(m, %Schema{cmd: cmd, acked: true, orphan: false, ack_at: at, rt_latency_us: us})
      when is_map(m) do
    put_status(m, %{cmd: map_cmd(cmd), acked: true, ack_at: at, rt_latency_us: us})
  end

  # (3 of 5) pending
  def status(m, %Schema{cmd: cmd, acked: false, sent_at: at}) when is_map(m) do
    put_status(m, %{cmd: map_cmd(cmd), pending: true, at: at})
  end

  # (4 of 5) orphan
  def status(m, %Schema{orphan: true, ack_at: at}) do
    put_status(m, %{cmd: :unknown, orphan: true, orphan_at: at})
  end

  # (5 of 5)
  def status(m, _) do
    import Helen.Time.Helper, only: [utc_now: 0]
    put_status(m, %{cmd: :unknown, invalid: true, at: utc_now()})
  end

  def update(refid, opts) when is_binary(refid) and is_list(opts) do
    cmd = find_refid(refid)

    if is_nil(cmd), do: {:not_found, refid}, else: update(cmd, opts)
  end

  def update(%Schema{} = c, opts) when is_list(opts) do
    p = Keyword.take(opts, columns(:update)) |> Enum.into(%{})
    cs = changeset(c, p)

    if cs.valid? do
      preloads = __MODULE__.__schema__(:associations)
      {:ok, Repo.update!(cs, returning: true) |> Repo.preload(preloads)}
    else
      {:invalid_changes, cs}
    end
  end
end
