defmodule PulseWidth.DB.Command do
  @moduledoc """
  Database functionality for PulseWidth Command
  """

  use Ecto.Schema
  use Broom

  alias PulseWidth.DB.Command, as: Schema
  alias PulseWidth.DB.{Alias, Device}

  schema "pwm_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:alias_id, :id)
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

  # primary entry point when called from Switch and an ack is needed
  # the single parameter is the reading that has been processed by
  # Device.upsert/1

  # this function returns the reading passed in unchanged
  def ack_if_needed(
        %{
          cmdack: true,
          refid: refid,
          msg_recv_dt: recv_dt,
          device: {:ok, %Device{}}
        } = msg
      ) do
    import PulseWidth.Fact.Command, only: [write_specific_metric: 2]
    import TimeSupport, only: [utc_now: 0]

    set_base_opts = [acked: true, ack_at: utc_now()]

    with %Schema{sent_at: sent_at} = cmd <- find_refid(refid),
         latency_us <- Timex.diff(recv_dt, sent_at, :microsecond),
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

  # primary entry point when called from Switch and an ack is not needed
  def ack_if_needed(%{device: {:ok, %Device{}}} = msg), do: msg

  # no match, just pass through
  def ack_if_needed(msg), do: msg

  def ack_immediate_if_needed({:pending, res} = rc, opts)
      when is_list(res) and is_list(opts) do
    import TimeSupport, only: [utc_now: 0]

    #
    # if ack: false (host expected to ack) then immediately ack
    #
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

  def add(%Device{} = x, %Alias{id: alias_id}, %DateTime{} = dt) do
    cmd = Ecto.build_assoc(x, :cmds) |> Map.put(:alias_id, alias_id)
    cs = changeset(cmd, sent_at: dt)

    insert_and_track(cs)
  end

  defp changeset(x, params) when is_map(params) or is_list(params) do
    import Ecto.Changeset,
      only: [cast: 3, validate_required: 2, unique_constraint: 3]

    cast(x, Enum.into(params, %{}), cast_cols())
    |> validate_required([:sent_at, :alias_id])
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
    cmd = find_refid(refid)

    if is_nil(cmd), do: {:not_found, refid}, else: update(cmd, opts)
  end

  def update(%Schema{} = cmd, opts) when is_list(opts) do
    set = Keyword.take(opts, possible_cols()) |> Enum.into(%{})
    cs = changeset(cmd, set)

    if cs.valid? do
      preloads = __MODULE__.__schema__(:associations)
      {:ok, Repo.update!(cs, returning: true) |> Repo.preload(preloads)}
    else
      {:invalid_changes, cs}
    end
  end

  #
  ## Changeset Helpers
  #
  defp cast_cols,
    do: [:acked, :orphan, :refid, :rt_latency_us, :sent_at, :ack_at, :alias_id]

  defp possible_cols,
    do: [
      :acked,
      :orphan,
      :alias_id,
      :rt_latency_us,
      :sent_at,
      :ack_at
    ]
end
