defmodule Sally.Command do
  @moduledoc false

  use Agent
  use Ecto.Schema
  use Alfred.Track, timeout_after: "PT3.3S"

  require Logger
  import Ecto.Query, only: [from: 2, join: 4, preload: 3]

  schema "command" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:track, :any, virtual: true)
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer, default: 0)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:dev_alias, Sally.DevAlias)
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

  def ack_orphan_now(%__MODULE__{} = cmd) do
    :ok = log_orphan_cmd(cmd)

    ack_now_cs(cmd, :orphan, now()) |> Sally.Repo.update!(@returned) |> save()
  end

  def add(%Sally.DevAlias{} = da, opts) do
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
    |> Sally.Repo.insert!(returning: true)
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

  def changeset(changes, %__MODULE__{} = c) when is_map(changes) do
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
    latest_cmd_query(dev_alias) |> Sally.Repo.one()
  end

  def latest_cmd_query(%Sally.DevAlias{id: dev_alias_id}) do
    Ecto.Query.from(cmd in __MODULE__,
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

  def purge(%Sally.DevAlias{cmds: cmds}, :all, batch_size \\ 10) do
    import Ecto.Query, only: [from: 2]

    all_ids = Enum.map(cmds, fn %__MODULE__{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, batch_size)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = from(c in __MODULE__, where: c.id in ^batch)

        {deleted, _} = Sally.Repo.delete_all(q)

        {:ok, acc + deleted}
    end
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
    |> tap(fn dev_alias -> status_log_unknown(dev_alias, name) end)
  end

  @unknown %{cmd: "unknown", acked: true}
  def status_log_unknown(%{status: @unknown}, name), do: Logger.warn(~s("#{name}"))
  def status_log_unknown(_what, _name), do: :ok

  def status_base_query(val, _opts) do
    cmd_fields = __schema__(:fields)

    field = if(is_binary(val), do: :name, else: :id)

    from(dev_alias in Sally.DevAlias,
      as: :dev_alias,
      where: field(dev_alias, ^field) == ^val,
      inner_lateral_join:
        latest in subquery(
          from(Sally.Command,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            order_by: [desc: :sent_at],
            limit: 1
          )
        ),
      select_merge: %{nature: :cmds, seen_at: dev_alias.updated_at, status: map(latest, ^cmd_fields)}
    )
  end

  def status_query(<<_::binary>> = name, opts) do
    query = status_base_query(name, opts)

    Enum.reduce(opts, query, fn
      {:preload, :device_and_host}, query ->
        query
        |> join(:inner, [dev_alias], device in assoc(dev_alias, :device))
        |> join(:inner, [_, _, device], host in assoc(device, :host))
        |> preload([_, _, device, host], device: {device, host: host})

      _, query ->
        query
    end)
  end

  def summary(%__MODULE__{} = x) do
    Map.take(x, [:cmd, :acked, :sent_at])
  end

  def summary([%__MODULE__{} = x | _]), do: summary(x)

  def summary([]), do: %{}

  @impl true
  def track_now?(%__MODULE__{} = cmd, opts) do
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
