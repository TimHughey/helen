defmodule Switch.DB.Device do
  @moduledoc """
  Database functionality for Switch Device
  """

  use Ecto.Schema

  alias Switch.DB.Alias, as: Alias
  alias Switch.DB.Command, as: Command
  alias Switch.DB.Device, as: Schema

  schema "switch_device" do
    field(:device, :string)
    field(:host, :string)

    embeds_many :states, State do
      field(:pio, :integer, default: nil)
      field(:state, :boolean, default: false)
    end

    field(:dev_latency_us, :integer)
    field(:ttl_ms, :integer, default: 60_000)
    field(:last_seen_at, :utc_datetime_usec)
    field(:last_cmd_at, :utc_datetime_usec)

    has_many(:cmds, Command, foreign_key: :device_id, references: :id)
    has_many(:aliases, Alias, foreign_key: :device_id, references: :id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def all(x), do: Repo.all(x)

  @doc false
  def add_cmd(%Schema{} = x, %Alias{} = a, %DateTime{} = dt) do
    import Ecto.Query, only: [from: 2]

    x = reload(x)
    %{cmd: {:ok, %Command{refid: refid}}} = Command.add(x, a, dt)

    {rc, x} = upsert(x, last_cmd_at: dt)

    cmd_query = from(c in Command, where: c.refid == ^refid)

    if rc == :ok,
      do: {:ok, reload(x) |> Repo.preload(cmds: cmd_query)},
      else: {rc, x}
  end

  @doc false
  def changeset(x, p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        cast_embed: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, Enum.into(p, %{}), keys(:cast))
    |> cast_embed(:states, with: &states_changeset/2, required: true)
    |> validate_required(keys(:required))
    |> validate_format(:device, name_regex())
    |> validate_format(:host, name_regex())
    |> validate_number(:dev_latency_us, greater_than_or_equal_to: 0)
    |> validate_number(:ttl_ms, greater_than_or_equal_to: 0)
  end

  @doc """
    Retrieve Switch Device names
  """
  @doc since: "0.0.21"
  def devices do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.device, order_by: x.device) |> Repo.all()
  end

  @doc """
    Retrieve switch device names that begin with a pattern
  """
  @doc since: "0.0.21"
  def devices_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]
    import IO, only: [iodata_to_binary: 1]

    like_string = iodata_to_binary([pattern, "%"])

    from(x in Schema,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> all()
  end

  @doc """
  Find the actual device struct using the name or id
  """
  def find(id_or_device) do
    check_args = fn
      x when is_binary(x) -> [device: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2]

    with opts when is_list(opts) <- check_args.(id_or_device),
         %Schema{} = found <- get_by(Schema, opts) |> preload() do
      found
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  def find_alias(
        %Schema{aliases: aliases},
        alias_name,
        alias_pio,
        _opts \\ []
      )
      when is_binary(alias_name) and is_integer(alias_pio) and alias_pio >= 0 do
    found =
      for %Alias{name: name, pio: pio} = x
          when name == alias_name and pio == alias_pio <- aliases,
          do: x

    if Enum.empty?(found),
      do: {:not_found, {alias_name, alias_pio}},
      else: {:ok, hd(found)}
  end

  @doc false
  def keys(:all) do
    drop =
      [:__meta__, :id, __schema__(:associations)]
      |> List.flatten()

    Map.from_struct(%Schema{})
    |> Map.drop(drop)
    |> Map.keys()
    |> List.flatten()
  end

  @doc false
  def keys(:cast) do
    keys_drop(:all, [__schema__(:embeds)])
  end

  @doc false
  def keys(:required),
    do: keys_drop(:all, [:inserted_at, :updated_at])

  @doc false
  def keys(:replace) do
    keys_drop(:all, [:device, :inserted_at])
  end

  @doc """
  Get the count of pios for a device by name or actual device struct
  """
  def pio_count(%Schema{states: states}), do: Enum.count(states)

  def pio_count(device) when is_binary(device) do
    sd = find(device)

    if is_nil(sd),
      do: {:not_found, device},
      else: pio_count(sd)
  end

  @doc false
  def pio_state(%Schema{} = sd, pio, opts \\ [])
      when is_integer(pio) and
             pio >= 0 and
             is_list(opts) do
    pio_state_actual(sd, pio, opts)
  end

  @doc false
  defp pio_state_actual(%Schema{device: device} = sd, pio, opts) do
    import Helen.Time.Helper, only: [ttl_check: 4]

    alias Switch.DB.Device.State, as: State

    find_fn = fn %State{pio: p} -> p == pio end

    with %Schema{states: states, last_seen_at: seen_at, ttl_ms: ttl_ms} <- sd,
         %State{state: state} <- Enum.find(states, find_fn) do
      ttl_check(seen_at, state, ttl_ms, opts)
    else
      _anything ->
        {:bad_pio, {device, pio}}
    end
  end

  # NOTE: the %_{} assignment match is any struct
  @doc false
  def preload(%_{} = x), do: preload_unacked_cmds(x) |> Repo.preload([:aliases])
  def preload(other), do: other

  @doc false
  def record_cmd(%Schema{} = sd, %Alias{} = sa, opts)
      when is_list(opts) do
    import Switch.Payload.Position, only: [send_cmd: 4]
    import Helen.Time.Helper, only: [utc_now: 0]

    sd = reload(sd)

    cmd_opts = Keyword.take(opts, [:ack])
    cmd_map = Keyword.get(opts, :cmd_map, {:bad_args, opts})

    with %{state: state, pio: pio} <- cmd_map,
         # add the command and pass initial_opts which may contain ack: false
         {:ok, %Schema{} = sd} <- add_cmd(sd, sa, utc_now()),
         # NOTE: add_cmd/3 returns the Device with the new Command preloaded
         {:cmd, %Command{refid: refid} = cmd} <- {:cmd, hd(sd.cmds)},
         {:refid, true} <- {:refid, is_binary(refid)},
         state_map <- %{pio: pio, state: state},
         pub_rc <- send_cmd(sd, cmd, state_map, cmd_opts) do
      {:pending, [position: state, refid: refid, pub_rc: pub_rc]}
    else
      error -> {:failed, error}
    end
  end

  @doc false
  def reload(%Schema{id: id}) do
    import Repo, only: [get!: 2]

    get!(Schema, id) |> preload()
  end

  @doc false
  def states_changeset(schema, params) do
    import Ecto.Changeset, only: [cast: 3]

    cast(schema, params, [:pio, :state])
  end

  @doc false
  def upsert(%{device: _, host: _, states: _} = msg) do
    import Helen.Time.Helper, only: [utc_now: 0]

    params = [
      :device,
      :host,
      :states,
      :dev_latency_us,
      :ttl_ms,
      :last_cmd_at,
      :last_seen_at
    ]

    params_default = %{last_cmd_at: utc_now(), last_seen_at: utc_now()}

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

  @doc false
  # Device.upsert/2 will insert or update a %Device{} using the map passed in
  def upsert(%Schema{} = x, params) when is_map(params) or is_list(params) do
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
      {:ok, preload(x)}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
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

  #
  # Changeset Lists
  #

  defp keys_drop(base_keys, drop) do
    drop = List.flatten(drop)

    MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
    |> MapSet.to_list()
  end
end
