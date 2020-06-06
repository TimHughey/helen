defmodule Switch.DB.Command do
  @moduledoc """
  Database functionality for Switch Command
  """

  use Ecto.Schema
  use Janitor

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
    #
    # base list of changes
    changes = [acked: true, ack_at: utc_now()]

    with {:cmd, %Schema{sent_at: sent_at} = cmd} <- {:cmd, find_refid(refid)},
         latency <- Timex.diff(recv_dt, sent_at, :microsecond),
         _ignore <- record_cmd_rt_metric(cmd, latency),
         changes <- [rt_latency_us: latency] ++ changes,
         {:ok, %Schema{}} <- update(cmd, changes) |> untrack() do
      msg
    else
      # handle the exception case when the refid wasn't found
      # NOTE:  this case should only occur when MQTT messages are
      #        processed from another environment during dev / test
      {:cmd, nil} -> Map.put(msg, :switch_cmd_ack_fault, {:cmd, nil})
      error -> Map.put(msg, :switch_cmd_ack_fault, error)
    end
  end

  # primary entry point when called from Switch and an ack is not needed
  def ack_if_needed(%{switch_device: {:ok, %Device{}}} = msg), do: msg

  # no match, just pass through
  def ack_if_needed(msg), do: msg

  def ack_immediate_if_needed({:pending, res} = rc, opts)
      when is_list(res) and is_list(opts) do
    #
    # if ack: false (host expected to ack) then immediately ack
    #
    unless Keyword.get(opts, :ack, true) do
      cmd = Keyword.get(res, :refid) |> find_refid()

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

  def add(%Device{} = sd, sw_alias, %DateTime{} = dt)
      when is_binary(sw_alias) do
    Ecto.build_assoc(
      sd,
      :cmds
    )
    |> changeset(sent_at: dt, sw_alias: sw_alias, acked: false, orphan: false)
    |> Repo.insert!(returning: true)
    |> track()
  end

  def find_refid(refid) when is_binary(refid),
    do: Repo.get_by(Schema, refid: refid) |> Repo.preload([:device])

  def find_refid(nil), do: nil

  def reload(%Schema{id: id}), do: reload(id)

  def reload(id) when is_integer(id),
    do: Repo.get_by(Schema, id: id) |> Repo.preload([:device])

  defp changeset(x, params) when is_map(params) or is_list(params) do
    import Ecto.Changeset,
      only: [cast: 3, validate_required: 2, unique_constraint: 3]

    cast(x, Enum.into(params, %{}), cast_changes())
    |> validate_required([:sw_alias, :acked, :orphan, :sent_at])
    |> unique_constraint(:refid, name: :switch_command_refid_index)
  end

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

  defp record_cmd_rt_metric(%Schema{sw_alias: device}, latency) do
    alias Fact.RunMetric

    RunMetric.record(
      module: "#{__MODULE__}",
      metric: "sw_cmd_rt_latency_us",
      device: device,
      val: latency
    )
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
