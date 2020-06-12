defmodule PulseWidth.DB.Command do
  @moduledoc """
    The PulseWidth.DB.Command module provides the database schema for tracking
    commands sent for a PulseWidth.
  """

  use Timex
  use Ecto.Schema

  import Ecto.Changeset

  use Janitor

  schema "pwm_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:acked, :boolean)
    field(:orphan, :boolean)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:ack_at, :utc_datetime_usec)
    belongs_to(:pwm, PulseWidth, foreign_key: :pwm_id)

    timestamps(type: :utc_datetime_usec)
  end

  alias PulseWidth.DB.Command, as: Schema

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
        {:ok, %PulseWidth{}},
        %{cmdack: true, refid: refid, msg_recv_dt: recv} = msg
      ) do
    import Repo, only: [get_by: 2]

    set_base_opts = [acked: true, ack_at: utc_now()]

    with {:ok, %Schema{sent_at: sent_at} = cmd} <- get_by(Schema, refid: refid),
         latency_us <- Timex.diff(recv, sent_at, :microsecond),
         set_opts <- Keyword.put(set_base_opts, :rt_latency_us, latency_us),
         {:ok, %Schema{}} <- update(cmd, set_opts) |> untrack() do
      msg
    else
      nil -> {:not_found, refid}
      {:invalid_changes, _cs} = rc -> rc
      error -> {:error, error}
    end
  end

  # if the above didn't match then an ack is not needed
  def ack_if_needed({:ok, %PulseWidth{}} = rc, %{}), do: rc

  def ack_now(refid, opts \\ []) do
    import Repo, only: [get_by: 2, preload: 2]

    with {:ok, %Schema{} = cmd} <- get_by(Schema, refid: refid),
         %Schema{} = cmd <- preload(cmd, [:pwm]),
         ack_map <- %{cmdack: true, refid: refid, msg_recv_dt: utc_now()},
         ack_map <- Map.merge(ack_map, Enum.into(opts, %{})) do
      ack_if_needed(cmd, ack_map)
    else
      nil -> {:not_found, refid}
      error -> {:error, error}
    end
  end

  def add(%PulseWidth{} = pwm, %DateTime{} = dt) do
    Ecto.build_assoc(
      pwm,
      :cmds,
      sent_at: dt
    )
    |> Repo.insert!(returning: true)
    |> track()
  end

  def reload(%Schema{id: id}), do: reload(id)

  def reload(id) when is_integer(id),
    do: Repo.get_by(__MODULE__, id: id) |> Repo.preload([:pwm])

  defp changeset(pwmc, params) when is_list(params),
    do: changeset(pwmc, Enum.into(params, %{}))

  defp changeset(pwmc, params) when is_map(params) do
    pwmc
    |> cast(params, possible_changes())
    |> validate_required(possible_changes())
    |> unique_constraint(:refid, name: :pwm_cmd_refid_index)
  end

  def update(refid, opts) when is_binary(refid) and is_list(opts) do
    import Repo, only: [get_by: 2]

    with %Schema{} = cmd <- get_by(Schema, refid: refid) do
      Repo.update(cmd, opts)
    else
      nil -> {:not_found, refid}
    end
  end

  def update(%Schema{} = pwmc, opts) when is_list(opts) do
    set = Keyword.take(opts, possible_changes()) |> Enum.into(%{})
    cs = changeset(pwmc, set)

    if cs.valid?,
      do: {:ok, Repo.update!(cs, returning: true) |> Repo.preload([:pwm])},
      else: {:invalid_changes, cs}
  end

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
