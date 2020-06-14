defmodule Switch.DB.Command do
  @moduledoc """
  Database functionality for Switch Command
  """

  use Ecto.Schema
  use Broom

  alias Switch.DB.Command, as: Schema
  alias Switch.DB.Device, as: Device

  schema "switch_command" do
    field(:sw_alias, :string)
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:acked, :boolean, default: false)
    field(:orphan, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:ack_at, :utc_datetime_usec)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id
    )

    timestamps(type: :utc_datetime_usec)
  end

  def acked?(refid) do
    cmd = find_refid(refid)

    if is_nil(cmd), do: false, else: cmd.acked
  end

  # primary entry point when called from Switch and an ack is needed
  # the single parameter is the reading that has been processed by
  # Device.upsert/1

  # this function returns the reading passed in unchanged
  def ack_if_needed(
        %{
          cmdack: true,
          refid: refid,
          msg_recv_dt: recv_dt,
          switch_device: {:ok, %Device{}}
        } = msg
      ) do
    import Broom, only: [release: 2]
    import Switch.Fact.Command, only: [write_specific_metric: 2]
    import TimeSupport, only: [utc_now: 0]
    #
    # base list of changes
    changes = [acked: true, ack_at: utc_now()]

    with %Schema{sent_at: sent_at} = cmd <- find_refid(refid),
         latency <- Timex.diff(recv_dt, sent_at, :microsecond),
         changes <- [rt_latency_us: latency] ++ changes,
         {:ok, %Schema{}} = cmd_rc <- update(cmd, changes),
         msg <- release(broom(), %{cmd: cmd_rc}),
         _ignore <- write_specific_metric(cmd_rc, msg) do
      msg
    else
      # handle the exception case when the refid wasn't found
      # NOTE:  this case should only occur when MQTT messages are
      #        processed from another environment during dev / test
      nil -> Map.put(msg, :cmd_ack_fault, {:cmd, nil})
      error -> Map.put(msg, :cmd_ack_fault, error)
    end
  end

  # primary entry point when called from Switch and an ack is not needed
  def ack_if_needed(%{switch_device: {:ok, %Device{}}} = msg), do: msg

  # no match, just pass through
  def ack_if_needed(msg), do: msg

  def ack_immediate_if_needed({:pending, res} = rc, opts)
      when is_list(res) and is_list(opts) do
    import TimeSupport, only: [utc_now: 0]

    #
    # if ack: false (host expected to ack) then immediately ack
    #
    unless Keyword.get(opts, :ack, true) do
      cmd = find_refid(res[:refid])

      if cmd do
        %Schema{device: sd, refid: refid} = cmd

        %{
          cmdack: true,
          refid: refid,
          msg_recv_dt: utc_now(),
          processed: {:ok, sd}
        }
        |> Map.merge(Enum.into(opts, %{}))
        |> ack_if_needed()
      end
    end

    rc
  end

  def ack_immediate_if_needed(rc, _opts), do: rc

  def add(%Device{} = x, sw_name, %DateTime{} = dt) when is_binary(sw_name) do
    cmd = Ecto.build_assoc(x, :cmds)
    cs = changeset(cmd, sw_alias: sw_name, sent_at: dt)

    insert_and_track(cs)
  end

  # def reload(%Schema{id: id}), do: reload(id)
  #
  # def reload(id) when is_integer(id),
  #   do: Repo.get_by(Schema, id: id) |> Repo.preload([:device])

  defp changeset(x, params) when is_map(params) or is_list(params) do
    import Ecto.Changeset,
      only: [cast: 3, validate_required: 2, unique_constraint: 3]

    cast(x, Enum.into(params, %{}), cast_changes())
    |> validate_required([:sw_alias, :sent_at])
    |> unique_constraint(:refid, name: :switch_command_refid_index)
  end

  def default_opt(),
    do: [
      orphan: [
        startup_check: true,
        sent_before: [seconds: 12],
        older_than: [minutes: 1]
      ],
      purge: [
        at_startup: true,
        interval: [minutes: 2],
        older_than: [days: 30]
      ],
      metrics: [minutes: 5]
    ]

  def update(refid, opts) when is_binary(refid) and is_list(opts) do
    cmd = find_refid(refid)

    if is_nil(cmd), do: {:not_found, refid}, else: update(cmd, opts)
  end

  def update(%Schema{} = cmd, opts) when is_list(opts) do
    set = Keyword.take(opts, possible_changes()) |> Enum.into(%{})
    cs = changeset(cmd, set)

    if cs.valid?,
      do: {:ok, Repo.update!(cs, returning: true)},
      else: {:invalid_changes, cs}
  end

  #
  ## Changeset Helpers
  #
  defp cast_changes,
    do: [:sw_alias, :acked, :orphan, :refid, :rt_latency_us, :sent_at, :ack_at]

  defp possible_changes,
    do: [
      :acked,
      :orphan,
      :rt_latency_us,
      :sent_at,
      :ack_at
    ]
end
