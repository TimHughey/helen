defmodule Sally.Command do
  @moduledoc false

  require Logger

  use Ecto.Schema
  use Alfred.Broom, timeout_after: "PT3.3S"

  require Ecto.Query

  alias __MODULE__, as: Schema
  alias Sally.{DevAlias, Repo}

  schema "command" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer, default: 0)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:dev_alias, DevAlias)
  end

  def ack_now_cs(multi_changes, disposition) do
    %{cmd_to_ack: cmd, recv_at: ack_at} = multi_changes

    orphaned = disposition == :orphan

    changes = %{acked: true, acked_at: ack_at, orphaned: orphaned} |> include_rt_latency(cmd)
    required = Map.keys(changes)

    Sally.Repo.load(__MODULE__, id: cmd.id)
    |> Ecto.Changeset.cast(changes, required)
  end

  def ack_orphan_now(nil), do: {:ok, :already_acked}

  def ack_orphan_now(%Schema{} = cmd) do
    changes = %{acked: true, acked_at: now(), orphaned: true} |> include_rt_latency(cmd)
    required = Map.keys(changes)

    Ecto.Changeset.cast(cmd, changes, required) |> Sally.Repo.update()
  end

  def add(%DevAlias{} = da, opts) do
    {cmd, opts_rest} = Keyword.pop(opts, :cmd)
    {cmd_opts, opts_rest} = Keyword.pop(opts_rest, :cmd_opts, [])
    {ref_dt, field_list} = Keyword.pop(opts_rest, :ref_dt, now())
    fields_map = Enum.into(field_list, %{})

    new_cmd = Ecto.build_assoc(da, :cmds)

    # handle special case of ack immediate
    ack_immediate? = cmd_opts[:ack] == :immediate

    # base changes for all new cmds
    %{
      refid: make_refid(),
      cmd: cmd,
      acked: ack_immediate?,
      acked_at: if(ack_immediate?, do: ref_dt, else: nil),
      sent_at: ref_dt
    }
    |> Map.merge(fields_map)
    |> changeset(new_cmd)
    |> Repo.insert!(returning: true)
  end

  @returned [returning: true]
  def align_cmd(%Sally.DevAlias{} = dev_alias, cmd, asis_cmd, multi_acc, multi_read_only) do
    log_cmd_mismatch(dev_alias, cmd, asis_cmd)

    multi_id = {:aligned, dev_alias.name, dev_alias.pio}
    align_cs = align_cmd_cs(dev_alias, cmd, multi_read_only)

    Ecto.Multi.insert(multi_acc, multi_id, align_cs, @returned)
  end

  def align_cmd_cs(dev_alias, cmd, multi_read_only) do
    align_cmd = Ecto.build_assoc(dev_alias, :cmds)

    %{
      refid: make_refid(),
      cmd: cmd,
      acked: true,
      acked_at: Timex.now(),
      sent_at: multi_read_only.dispatch.sent_at,
      rt_latency_us: 1000
    }
    |> changeset(align_cmd)
  end

  # NOTE: returns => {:ok, schema} __OR__ {:ok, already_acked}
  @impl true
  def broom_timeout(%Alfred.Broom{tracked_info: %{id: id}}) do
    # NOTE: there could be a race condition, only retrieve unacked cmd
    Ecto.Query.from(cmd in __MODULE__, where: [id: ^id, acked: false])
    |> Sally.Repo.one()
    |> ack_orphan_now()
  end

  def changeset(changes, %Schema{} = c) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:refid, :cmd, :sent_at, :dev_alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    # NOTE: optimize the length of a refid
    |> Changeset.validate_length(:refid, min: 8, max: 36)
    |> Changeset.unique_constraint(:refid)
  end

  def log_cmd_mismatch(dev_alias, pin_cmd, asis_cmd) do
    [
      module: __MODULE__,
      name: dev_alias.name,
      align_status: true,
      mismatch: true,
      asis_cmd: asis_cmd,
      reported_cmd: pin_cmd
    ]
    |> Betty.app_error_v2()
  end

  @cast_cols [:refid, :cmd, :acked, :orphaned, :rt_latency_us, :sent_at, :acked_at]
  def columns(:cast), do: @cast_cols

  def check_stale(%{refid: refid} = cmd) do
    tracked_info = tracked_info(refid)

    case tracked_info do
      %{refid: ^refid} -> :tracked
      _ -> ack_orphan_now(cmd)
    end
  end

  @doc false
  def include_rt_latency(%{acked_at: ack_at} = changes, %{sent_at: sent_at} = _cmd) do
    changes |> Map.put(:rt_latency_us, Timex.diff(ack_at, sent_at))
  end

  def latest(%Sally.DevAlias{} = dev_alias, :id) do
    latest_query(dev_alias, :id) |> Sally.Repo.one()
  end

  def latest_query(%Sally.DevAlias{id: dev_alias_id}, :id) do
    Ecto.Query.from(cmd in Schema,
      # distinct: cmd.dev_alias_id,
      where: [dev_alias_id: ^dev_alias_id],
      order_by: [desc: :sent_at],
      limit: 1
    )
  end

  @default_pin [0, "no pin"]
  def pin_cmd(pin_data, pio) do
    # NOTE: pin data shape: [[pin_num, pin_cmd], ...]
    Enum.find(pin_data, @default_pin, &match?([^pio, _], &1)) |> Enum.at(1)
  end

  # @doc """
  # Load the `Sally.DevAlias`, if needed
  # """
  # @doc since: "0.5.15"
  # def load_dev_alias(cmd) when is_struct(cmd) or is_nil(cmd) do
  #   cmd |> Repo.preload(:dev_alias)
  # end

  def purge(%DevAlias{cmds: cmds}, :all, batch_size \\ 10) do
    import Ecto.Query, only: [from: 2]

    all_ids = Enum.map(cmds, fn %Schema{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, batch_size)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = from(c in Schema, where: c.id in ^batch)

        {deleted, _} = Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  def query_preload_latest_cmd do
    import Ecto.Query, only: [from: 2]

    from(c in Schema, distinct: c.dev_alias_id, order_by: [desc: c.sent_at])
  end

  def reported_cmd_changeset(%DevAlias{} = da, cmd, reported_at) do
    reported_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # grab the current time for sent_at and possibly acked_at (when ack: :immediate)
    utc_now = DateTime.utc_now()

    %{refid: refid, cmd: cmd, acked: true, orphan: false, acked_at: utc_now, sent_at: reported_at}
    |> changeset(reported_cmd)
  end

  def status(%Sally.DevAlias{} = dev_alias, opts) do
    query = latest_query(dev_alias, :id)

    case Sally.Repo.one(query) do
      %Sally.Command{} = cmd -> cmd
      nil -> status_fix_missing_cmd(dev_alias, opts)
    end
    |> status_finalize(dev_alias)
  end

  def status_finalize(%Sally.Command{} = cmd, %Sally.DevAlias{} = dev_alias) do
    fields = Map.take(dev_alias, [:id | Sally.DevAlias.columns(:all)])

    Sally.Repo.load(Sally.DevAlias, fields)
    |> struct(cmds: [cmd])
  end

  @doc false
  def status_fix_missing_cmd(%Sally.DevAlias{} = dev_alias, opts) do
    ["\n         correcting missing cmd [#{dev_alias.name}]"] |> Logger.warn()

    opts = Keyword.merge(opts, cmd: "unknown", cmd_opts: [ack: :immediate])

    add(dev_alias, opts)
  end

  def status_query(<<_::binary>> = name, _opts) do
    require Ecto.Query

    Ecto.Query.from(dev_alias in Sally.DevAlias,
      as: :dev_alias,
      where: [name: ^name],
      join: cmd in assoc(dev_alias, :cmds),
      inner_lateral_join:
        latest_cmd in subquery(
          Ecto.Query.from(Sally.Command,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            order_by: [desc: :sent_at],
            group_by: [:id, :dev_alias_id, :sent_at],
            limit: 1,
            select: [:id]
          )
        ),
      on: latest_cmd.id == cmd.id,
      preload: [cmds: cmd]
    )
  end

  def summary(%Schema{} = x) do
    Map.take(x, [:cmd, :acked, :sent_at])
  end

  def summary([%Schema{} = x | _]), do: summary(x)

  def summary([]), do: %{}
end
