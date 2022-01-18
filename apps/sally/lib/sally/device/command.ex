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
    |> Changeset.validate_length(:refid, is: 8)
    |> Changeset.unique_constraint(:refid)
  end

  def columns(:cast), do: [:refid, :cmd, :acked, :orphaned, :rt_latency_us, :sent_at, :acked_at]

  def add(%DevAlias{} = da, cmd, opts) do
    new_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # grab the current time for sent_at and possibly acked_at (when ack: :immediate)
    sent_at = opts[:sent_at] || DateTime.utc_now()

    # handle special case of ack immediate
    ack_immediate? = opts[:ack] == :immediate
    acked_at = if ack_immediate?, do: sent_at, else: nil

    # base changes for all new cmds
    %{refid: refid, cmd: cmd, acked: ack_immediate?, acked_at: acked_at, sent_at: sent_at}
    |> changeset(new_cmd)
    |> Repo.insert!(returning: true)
  end

  def add_v2(%DevAlias{} = da, opts) do
    {cmd, opts_rest} = Keyword.pop(opts, :cmd)
    {cmd_opts, opts_rest} = Keyword.pop(opts_rest, :cmd_opts, [])
    {ref_dt, _opts_rest} = Keyword.pop(opts_rest, :ref_dt, now())

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
    |> changeset(new_cmd)
    |> Repo.insert!(returning: true)
  end

  @doc false
  def include_rt_latency(%{acked_at: ack_at} = changes, %{sent_at: sent_at} = _cmd) do
    changes |> Map.put(:rt_latency_us, Timex.diff(ack_at, sent_at))
  end

  def load(id) when is_integer(id) do
    case Repo.get(Schema, id) do
      %Schema{} = x -> {:ok, x}
      _ -> {:error, :not_found}
    end
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

  def query_preload_latest_cmd(dev_alias_id) do
    import Ecto.Query, only: [from: 2]

    from(c in Schema,
      distinct: c.dev_alias_id,
      order_by: [desc: c.sent_at],
      where: [dev_alias_id: ^dev_alias_id]
    )
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

  def status(name, opts) do
    query = status_query(name, opts)

    case Sally.Repo.one(query) do
      %Sally.DevAlias{} = dev_alias -> dev_alias
      nil -> status_fix_missing_cmd(name, opts) |> status(opts)
    end
  end

  @doc false
  def status_fix_missing_cmd(name, opts) do
    opts = Keyword.merge(opts, cmd: "unknown", cmd_opts: [ack: :immediate])

    Sally.DevAlias.find(name) |> add_v2(opts)

    name
  end

  def status_query(<<_::binary>> = name, _opts) do
    require Ecto.Query

    Ecto.Query.from(dev_alias in Sally.DevAlias,
      as: :dev_alias,
      where: [name: ^name],
      join: cmds in assoc(dev_alias, :cmds),
      inner_lateral_join:
        latest_cmd in subquery(
          Ecto.Query.from(Sally.Command,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            order_by: [desc: :sent_at],
            limit: 1
          )
        ),
      on: latest_cmd.id == cmds.id,
      preload: [cmds: cmds]
    )
  end

  def summary(%Schema{} = x) do
    Map.take(x, [:cmd, :acked, :sent_at])
  end

  def summary([%Schema{} = x | _]), do: summary(x)

  def summary([]), do: %{}
end
