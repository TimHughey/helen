defmodule Sally.Command do
  @moduledoc false

  require Logger
  use Agent
  use Ecto.Schema
  use Alfred.Track, timeout_after: "PT3.3S"

  require Ecto.Query

  alias __MODULE__, as: Schema
  alias Sally.{DevAlias, Repo}

  schema "command" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:track, :any, virtual: true)
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer, default: 0)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:dev_alias, DevAlias)
  end

  @returned [returning: true]

  def ack_now(%{id: _id} = cmd) do
    ack_now_cs(cmd, :ack, Timex.now())
    |> Sally.Repo.update!(@returned)
    # NOTE: updated the busy Command with the just acked Command
    |> save()
  end

  def ack_now_cs(%{id: _id} = cmd, disposition, %DateTime{} = ack_at) do
    orphaned = disposition == :orphan

    changes = %{acked: true, acked_at: ack_at, orphaned: orphaned} |> rt_latency_put(cmd)
    required = Map.keys(changes)

    cmd |> Ecto.Changeset.cast(changes, required)
  end

  def ack_orphan_now(nil), do: {:ok, :already_acked}

  def ack_orphan_now(%Schema{} = cmd) do
    :ok = log_orphan_cmd(cmd)

    ack_now_cs(cmd, :orphan, now()) |> Sally.Repo.update!(@returned) |> save()
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
    |> track(cmd_opts)
    |> save()
  end

  @immediate [ack: :immediate]
  @add_unknown_cmd [cmd: "unknown", cmd_opts: @immediate]
  def add_unknown(what, opts) do
    case what do
      <<_::binary>> = name ->
        Sally.Repo.get_by!(Sally.DevAlias, name: name) |> add_unknown(opts)

      %Sally.DevAlias{} = dev_alias ->
        cmd = add(dev_alias, Keyword.merge(opts, @add_unknown_cmd))
        struct(dev_alias, cmds: [cmd])
    end
  end

  @dont_notify [notify_when_released: false]
  def align_cmd(%{pio: pio} = dev_alias, pin_data, align_at) do
    pin_cmd = Sally.Command.pin_cmd(pio, pin_data)

    latest_cmd = latest_cmd(dev_alias)

    # NOTE: when a command is busy sent it to track. either the  ack from t
    # he host hasn't arrived (already tracked) or something is truly wrong.
    # by tracking it the timeout will eventually fire and tidy things up.
    case latest_cmd do
      # NOTE: busy commads _should_ aleady be tracked, otherwise it will timeout
      %{acked: false, acked_at: nil} = cmd -> {:busy, track(cmd, @dont_notify)}
      %{acked: true, cmd: ^pin_cmd, orphaned: false} -> {:aligned, pin_cmd}
      _ -> align_cmd_force(dev_alias, pin_cmd, align_at)
    end
  end

  def align_cmd_force(dev_alias, pin_cmd, align_at) do
    :ok = log_aligned_cmd(dev_alias, pin_cmd)

    add(dev_alias, cmd: pin_cmd, ref_dt: align_at, cmd_opts: @immediate)
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

  @cast_cols [:refid, :cmd, :acked, :orphaned, :rt_latency_us, :sent_at, :acked_at]
  def columns(:cast), do: @cast_cols

  def latest_cmd(%Sally.DevAlias{} = dev_alias) do
    latest_cmd(dev_alias, :query) |> Sally.Repo.one()
  end

  def latest_cmd(%Sally.DevAlias{id: dev_alias_id}, :query) do
    Ecto.Query.from(cmd in Schema,
      where: [dev_alias_id: ^dev_alias_id],
      order_by: [desc: :sent_at],
      limit: 1
    )
  end

  def log_aligned_cmd(dev_alias, pin_cmd) do
    [~s("), dev_alias.name, ~s("), " [", pin_cmd, "]"]
    |> Logger.info()
  end

  def log_orphan_cmd(%{id: _} = cmd) do
    cmd = Sally.Repo.preload(cmd, [:dev_alias])

    [~s("), cmd.dev_alias.name, ~s("), " [", cmd.cmd, "]"]
    |> Logger.info()
  end

  @default_pin [0, "no pin"]
  def pin_cmd(pio, pin_data) do
    # NOTE: pin data shape: [[pin_num, pin_cmd], ...]
    Enum.find(pin_data, @default_pin, &match?([^pio, _], &1))
    |> Enum.at(1)
  end

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

  @doc false
  def rt_latency_put(changes, cmd) do
    Map.put(changes, :rt_latency_us, Timex.diff(changes.acked_at, cmd.sent_at))
  end

  def status(<<_::binary>> = name, opts) do
    query = status_query(name, opts)

    case Sally.Repo.one(query) do
      %Sally.DevAlias{} = dev_alias -> dev_alias
      nil -> add_unknown(name, opts) |> then(fn _x -> status(name, opts) end)
    end
    |> status_log_unknown(name)
    |> then(fn %{cmds: [cmd]} = dev_alias -> struct(dev_alias, nature: :cmds, status: cmd) end)
  end

  @unknown %{cmd: "unknown", acked: true}
  def status_log_unknown(what, name) do
    case what do
      @unknown -> Logger.warn(~s("#{name}"))
      %{cmds: [@unknown]} -> Logger.warn(~s("#{name}"))
      _ -> :ok
    end

    what
  end

  def status_query(<<_::binary>> = name, _opts) do
    import Ecto.Query, only: [from: 2]

    from(da in Sally.DevAlias,
      as: :dev_alias,
      where: da.name == ^name,
      join: c in assoc(da, :cmds),
      inner_lateral_join:
        latest in subquery(
          from(Schema,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            order_by: [desc: :sent_at],
            limit: 1,
            select: [:id]
          )
        ),
      on: latest.id == c.id,
      preload: [cmds: c]
    )
  end

  # def status_query(<<_::binary>> = name, _opts) do
  #   require Ecto.Query
  #
  #   Ecto.Query.from(dev_alias in Sally.DevAlias,
  #     as: :dev_alias,
  #     where: [name: ^name],
  #     join: cmd in assoc(dev_alias, :cmds),
  #     inner_lateral_join:
  #       latest_cmd in subquery(
  #         Ecto.Query.from(cmd in Schema,
  #           distinct: [desc: cmd.sent_at],
  #           where: [dev_alias_id: parent_as(:dev_alias).id],
  #           order_by: [desc: :sent_at],
  #           select: [:id]
  #         )
  #       ),
  #     on: latest_cmd.id == cmd.id,
  #     preload: [cmds: cmd]
  #   )
  # end

  # def status_query(%Sally.DevAlias{id: dev_alias_id}, :id) do
  #   Ecto.Query.from(cmd in Schema,
  #     where: [dev_alias_id: ^dev_alias_id],
  #     order_by: [desc: :sent_at],
  #     limit: 1
  #   )
  # end

  def summary(%Schema{} = x) do
    Map.take(x, [:cmd, :acked, :sent_at])
  end

  def summary([%Schema{} = x | _]), do: summary(x)

  def summary([]), do: %{}

  @impl true
  def track_now?(%Sally.Command{} = cmd, opts) do
    track? = Keyword.get(opts, :track, true)

    track? and match?(%{acked: false}, cmd)
  end

  # NOTE: returns => {:ok, schema} __OR__ {:ok, already_acked}
  @impl true
  def track_timeout(%Alfred.Track{tracked_info: %{id: id}}) do
    # NOTE: there could be a race condition, only retrieve unacked cmd
    Sally.Repo.get_by(__MODULE__, id: id)
    |> ack_orphan_now()
  end

  ##
  ## Agent
  ##

  def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def to_binary(schema) do
    case schema do
      %{cmd: cmd} -> cmd
      _ -> "unknown"
    end
  end

  def agent(action, args) do
    case action do
      :find -> Agent.get(__MODULE__, __MODULE__, :__find, [args])
      :save -> Agent.update(__MODULE__, __MODULE__, :__save, [args])
      :all -> Agent.get(__MODULE__, fn cmds -> cmds end)
    end
  end

  def busy(what) do
    case agent(:find, what) do
      %{acked: false, acked_at: nil} = cmd -> cmd
      _ -> nil
    end
  end

  def busy?(what), do: busy(what) |> is_struct()
  def save(%Sally.Command{} = cmd), do: tap(cmd, fn cmd -> agent(:save, cmd) end)
  def saved(%Sally.DevAlias{} = dev_alias), do: agent(:find, dev_alias)
  def saved(<<_::binary>> = refid), do: agent(:find, refid)
  def saved_count, do: agent(:all, []) |> length()

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def cmd_match?(what, cmd) do
    compare = compare(what)

    compare == Map.take(cmd, Map.keys(compare))
  end

  def compare(id) when is_integer(id), do: %{dev_alias_id: id}
  def compare(%Sally.DevAlias{id: id}), do: %{dev_alias_id: id}
  def compare(%Sally.Command{} = cmd), do: Map.take(cmd, [:id, :refid])
  def compare(<<_::binary>> = refid), do: %{refid: refid}

  # NOTE: double underscore functions can only be called by the Agent
  def __find(cmds, <<_::binary>> = refid), do: Enum.find(cmds, &match?(%{refid: ^refid}, &1))
  def __find(cmds, what), do: Enum.find(cmds, &cmd_match?(what, &1))
  def __save(cmds, %{dev_alias_id: id} = cmd), do: [cmd | remove_saved(cmds, id)]
  def remove_saved(cmds, id), do: Enum.reject(cmds, &cmd_match?(id, &1))
end
