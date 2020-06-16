defmodule PulseWidth.DB.Command do
  @moduledoc """
    The PulseWidth.DB.Command module provides the database schema for tracking
    commands sent for a PulseWidth.
  """

  use Timex
  use Ecto.Schema

  import Ecto.Changeset

  use Broom

  alias PulseWidth.DB.Command, as: Schema
  alias PulseWidth.DB.Device, as: Device

  schema "pwm_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:acked, :boolean, default: false)
    field(:orphan, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:ack_at, :utc_datetime_usec)
    belongs_to(:device, Device, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  def acked?(refid) do
    import Repo, only: [get_by: 2]

    with %Schema{} <- get_by(Schema, refid: refid) do
      true
    else
      nil -> false
    end
  end

  # primary entry point when called from PulseWidth and an ack is needed
  # checks the return code from the update to the PulseWidth
  def ack_if_needed(
        %{
          cmdack: true,
          refid: refid,
          msg_recv_dt: recv,
          # NOTE:  the %_{} match is any struct
          device: {:ok, %_{}}
        } = msg
      ) do
    import Repo, only: [get_by: 2]
    import PulseWidth.Fact.Command, only: [write_specific_metric: 2]
    import TimeSupport, only: [utc_now: 0]

    set_base_opts = [acked: true, ack_at: utc_now()]

    with %Schema{sent_at: sent_at} = cmd <- find_refid(refid),
         latency_us <- Timex.diff(recv, sent_at, :microsecond),
         set_opts <- Keyword.put(set_base_opts, :rt_latency_us, latency_us),
         {:ok, %Schema{}} = cmd_rc <- update(cmd, set_opts),
         msg <- Map.put(msg, :cmd, cmd_rc) |> release(),
         _ignore <- write_specific_metric(cmd_rc, msg) do
      msg
    else
      nil -> Map.put(msg, :pwm_cmd_ack_fault, {:cmd, nil})
      error -> Map.put(msg, :pwm_cmd_ack_fault, error)
    end
  end

  # if the above didn't match then an ack is not needed
  def ack_if_needed(%{device: {:ok, %_{}}} = msg), do: msg

  # no match, just pass through
  def ack_if_needed(msg), do: msg

  def ack_immediate_if_needed({:pending, res} = rc, opts) do
    import Repo, only: [get_by: 2, preload: 2]
    import TimeSupport, only: [utc_now: 0]

    unless opts[:ack] do
      cmd = find_refid(res[:refid])

      if cmd do
        %Schema{device: dev, refid: refid} = cmd

        %{
          cmdack: true,
          refid: refid,
          msg_recv_dt: utc_now(),
          processed: {:ok, dev}
        }
        |> Map.merge(Enum.into(opts, %{}))
        |> ack_if_needed()
      end
    end

    rc
  end

  def ack_immediate_if_needed(rc, _opts), do: rc

  def add(%Device{} = x, %DateTime{} = dt) do
    cmd = Ecto.build_assoc(x, :cmds)
    cs = changeset(cmd, sent_at: dt)

    insert_and_track(cs)
  end

  # def reload(%Schema{id: id}), do: reload(id)
  #
  # def reload(id) when is_integer(id),
  #   do: Repo.get_by(__MODULE__, id: id) |> Repo.preload([:device])

  defp changeset(x, params) when is_list(params),
    do: changeset(x, Enum.into(params, %{}))

  defp changeset(x, params) do
    cast(x, Enum.into(params, %{}), cast_changes())
    |> validate_required([:sent_at])
    |> unique_constraint(:refid, name: :pwm_cmd_refid_index)
  end

  def default_opts,
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
    import Repo, only: [get_by: 2]

    with %Schema{} = cmd <- get_by(Schema, refid: refid) do
      Repo.update(cmd, opts)
    else
      nil -> {:not_found, refid}
    end
  end

  def update(%Schema{} = x, opts) when is_list(opts) do
    set = Keyword.take(opts, possible_changes()) |> Enum.into(%{})
    cs = changeset(x, set)

    if cs.valid?,
      do: {:ok, Repo.update!(cs, returning: true) |> Repo.preload([:device])},
      else: {:invalid_changes, cs}
  end

  #
  ## Changeset Helpers
  #
  defp cast_changes,
    do: [:acked, :orphan, :refid, :rt_latency_us, :sent_at, :ack_at]

  defp possible_changes,
    do: [
      :refid,
      :acked,
      :orphan,
      :rt_latency_us,
      :sent_at,
      :ack_at
    ]
end
