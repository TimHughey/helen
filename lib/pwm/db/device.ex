defmodule PulseWidth.DB.Device do
  @moduledoc """
  Database implementation of PulseWidth devices
  """

  require Logger

  alias PulseWidth.DB.Alias, as: Alias
  alias PulseWidth.DB.Command, as: Command
  alias PulseWidth.DB.Device, as: Schema

  use Ecto.Schema

  schema "pwm_device" do
    field(:device, :string)
    field(:host, :string)
    field(:duty, :integer, default: 0)
    field(:duty_max, :integer, default: 8191)
    field(:duty_min, :integer, default: 0)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)
    field(:last_cmd_at, :utc_datetime_usec)

    has_many(:cmds, Command, foreign_key: :device_id)
    has_one(:_alias_, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Deletes all PulseWidth devices
  """
  @doc since: "0.0.25"
  def delete_all(:dangerous) do
    import Ecto.Query, only: [from: 2]

    for x <- from(x in Schema, select: [:id]) |> Repo.all() do
      Repo.delete(x)
    end
  end

  @doc """
    Find the alias of a PulseWidth device
  """
  @doc since: "0.0.25"
  def device_find_alias(device_or_id) do
    with %Schema{_alias_: dev_alias} <- find(device_or_id) do
      dev_alias
    else
      _not_found -> {:not_found, device_or_id}
    end
  end

  @doc """
    Get a PulseWidth Device id or device

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Device{}

      ## Examples
        iex> PulseWidth.DB.Device.find("default")
        %Device{}
  """
  @doc since: "0.0.25"
  def find(id_or_device) do
    check_args = fn
      x when is_binary(x) -> [device: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2, preload: 2]

    with opts when is_list(opts) <- check_args.(id_or_device),
         %Schema{} = found <-
           get_by(Schema, opts)
           |> preload_unacked_cmds()
           |> Repo.preload(:_alias_) do
      found
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  def find_by_device(device) when is_binary(device),
    do: Repo.get_by(Schema, device: device)

  # NOTE: the %_{} assignment match is any struct
  def preload(%_{} = x), do: preload_unacked_cmds(x) |> Repo.preload([:_alias_])

  def record_cmd(%Schema{} = d, %Alias{}, opts) when is_list(opts) do
    import PulseWidth.Payload.Duty, only: [send_cmd: 3]
    import TimeSupport, only: [utc_now: 0]

    {cmd_opts, record_opts} = Keyword.split(opts, [:ack])
    cmd_map = record_opts[:cmd_map] || {:bad_args, opts}

    with %{cmd: {:ok, %Command{refid: refid}}} <- Command.add(d, utc_now()),
         # the command was inserted, now update the device last_cmd_at
         {:ok, device} <- update(d, last_cmd_at: utc_now()),
         %_{cmds: [%{refid: ref}]} = device <- preload_last_cmd(device, refid),
         pub_rc <- send_cmd(device, cmd_map, cmd_opts) do
      {:pending, [duty: cmd_map[:duty], refid: ref, pub_rc: pub_rc]}
    else
      %{cmd: {_, _} = rc} -> {:failed, {:cmd, rc}}
      error -> {:failed, error}
    end
  end

  def reload({:ok, %Schema{id: id}}), do: reload(id)

  def reload(%Schema{id: id}), do: reload(id)

  def reload(id) when is_number(id), do: Repo.get_by!(Schema, id: id)

  def reload(catchall) do
    Logger.warn(["update() failed: ", inspect(catchall, pretty: true)])
    {:error, catchall}
  end

  def update(name, opts) when is_binary(name) and is_list(opts) do
    pwm = find(name)

    if is_nil(pwm), do: {:not_found, name}, else: update(pwm, opts)
  end

  def update(%Schema{} = pwm, opts) when is_list(opts) do
    set = Keyword.take(opts, keys(:update)) |> Enum.into(%{})

    cs = changeset(pwm, set)

    if cs.valid?,
      do: {:ok, Repo.update(cs, stale_error_field: :stale_error) |> reload()},
      else: {:invalid_changes, cs}
  end

  def upsert(%{device: _, host: _, mtime: mtime} = msg) do
    import TimeSupport, only: [from_unix: 1, utc_now: 0]

    params = [
      :device,
      :host,
      :duty,
      :duty_max,
      :duty_min,
      :dev_latency_us,
      :discovered_at,
      :last_cmd_at,
      :last_seen_at
    ]

    params_default = %{
      discovered_at: from_unix(mtime),
      last_cmd_at: utc_now(),
      last_seen_at: utc_now()
    }

    # assemble a map of changes
    # NOTE:  the second map passed to Map.merge/2 replaces duplicate keys
    #        in the first map.  in this case we want all available data from
    #        the message however if some isn't available we provide it via
    #        changes_default
    params = Map.merge(params_default, Map.take(msg, params))

    # assemble the return message with the results of upsert/2
    # and send it through Command.ack_if_needed/1
    Map.put(msg, :device, upsert(%Schema{}, params))
    |> Command.ack_if_needed()
  end

  # Device.upsert/2 will insert or update a %Device{} using the map passed in
  def upsert(%Schema{} = x, params) when is_map(params) or is_list(params) do
    import Repo, only: [preload: 2]

    # make certain the params are a map
    params = Enum.into(params, %{})

    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys(:replace)},
      returning: true,
      conflict_target: [:device]
    ]

    cs = changeset(x, params)

    with {cs, true} <- {cs, cs.valid?()},
         # the keys on_conflict: and conflict_target: indicate the insert
         # is an "upsert"
         {:ok, %Schema{id: _id} = x} <- Repo.insert(cs, opts) do
      {:ok, x |> preload(Schema.__schema__(:associations))}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  defp changeset(pwm, params) when is_list(params),
    do: changeset(pwm, Enum.into(params, %{}))

  defp changeset(pwm, params) when is_map(params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    pwm
    |> cast(params, keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:device, name_regex())
    |> validate_number(:duty, greater_than_or_equal_to: 0)
    |> validate_number(:duty_min, greater_than_or_equal_to: 0)
    |> validate_number(:duty_max, greater_than_or_equal_to: 0)
  end

  # Keys For Updating, Creating a PulseWidth
  def keys(:all) do
    drop =
      [:__meta__, __schema__(:associations), __schema__(:primary_key)]
      |> List.flatten()

    %Schema{}
    |> Map.from_struct()
    |> Map.drop(drop)
    |> Map.keys()
    |> List.flatten()
  end

  def keys(:cast), do: keys(:all)

  def keys(:required),
    do: keys_drop(:all, [:id, :inserted_at, :updated_at])

  def keys(:replace),
    do: keys_drop(:all, [:device, :discovered_at, :inserted_at])

  def keys(:update),
    do: keys_drop(:all, [:device, :inserted_at, :updated_at])

  def keys(:upsert), do: keys_drop(:all, [:device, :inserted_at])

  defp keys_drop(base_keys, drop) do
    base = keys(base_keys) |> MapSet.new()
    remove = MapSet.new(drop)
    MapSet.difference(base, remove) |> MapSet.to_list()
  end

  defp preload_last_cmd(x, refid) do
    import Ecto.Query, only: [from: 2]

    Repo.preload(x, cmds: from(c in Command, where: c.refid == ^refid))
  end

  defp preload_unacked_cmds(x, limit \\ 1) do
    import Ecto.Query, only: [from: 2]

    Repo.preload(x,
      cmds:
        from(d in Command,
          where: d.acked == false,
          order_by: [desc: d.inserted_at],
          limit: ^limit
        )
    )
  end
end
