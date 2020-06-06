defmodule PulseWidth do
  @moduledoc """
    The PulseWidth module provides the base of a sensor reading.
  """

  require Logger
  use Timex
  use Ecto.Schema

  schema "pwm" do
    field(:name, :string)
    field(:description, :string)
    field(:device, :string)
    field(:host, :string)
    field(:duty, :integer, default: 0)
    field(:running_cmd, :string, default: "none")
    field(:duty_max, :integer, default: 8191)
    field(:duty_min, :integer, default: 0)
    field(:dev_latency_us, :integer, default: 0)
    field(:log, :boolean, default: false)
    field(:ttl_ms, :integer, default: 60_000)
    field(:reading_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)
    field(:last_cmd_at, :utc_datetime_usec)

    has_many(:cmds, PulseWidthCmd, foreign_key: :pwm_id)

    timestamps(type: :utc_datetime_usec)
  end

  def add(%{device: device, host: _host, mtime: mtime} = r) do
    import TimeSupport, only: [from_unix: 1]

    pwm = %PulseWidth{
      # the PulseWidth name defaults to the device when adding
      name: device,
      reading_at: from_unix(mtime),
      last_seen_at: from_unix(mtime),
      discovered_at: from_unix(mtime)
    }

    [Map.merge(pwm, Map.take(r, keys(:create)))] |> add()
  end

  def add(list) when is_list(list) do
    for %PulseWidth{} = p <- list do
      add(p)
    end
  end

  def add(%PulseWidth{name: _name, device: device} = p) do
    cs = changeset(p, Map.take(p, keys(:create)))

    with {:cs_valid, true} <- {:cs_valid, cs.valid?()},
         # the on_conflict: and conflict_target: indicate the insert
         # is an "upsert"
         {:ok, %PulseWidth{id: _id}} <-
           Repo.insert(cs,
             on_conflict: :replace_all,
             conflict_target: :device
           ),
         %PulseWidth{} = pwm <- find_by_device(device) do
      {:ok, pwm}
    else
      {:cs_valid, false} ->
        Logger.warn([
          "add() invalid changes: ",
          inspect(cs, pretty: true)
        ])

        {:invalid_changes, cs}

      {:error, rc} ->
        Logger.warn([
          "add() failed to insert: ",
          inspect(p, pretty: true),
          " rc: ",
          inspect(rc, pretty: true)
        ])

        {:error, rc}

      error ->
        Logger.warn(["add() failure: ", inspect(error, pretty: true)])

        {:failed, error}
    end
  end

  def add(catchall), do: {:bad_args, catchall}

  def add_cmd(%PulseWidth{} = pwm, %DateTime{} = dt) do
    import Ecto.Query, only: [from: 2]

    cmd = PulseWidthCmd.add(pwm, dt)

    {rc, pwm} = update(pwm, last_cmd_at: dt)

    cmd_query = from(c in PulseWidthCmd, where: c.refid == ^cmd.refid)

    if rc == :ok,
      do: {:ok, Repo.preload(pwm, cmds: cmd_query)},
      else: {rc, pwm}
  end

  @doc """
    Send a basic sequence to a PulseWidth found by name or actual struct

    PulseWidth.basic(name, basic: %{})
  """
  @doc since: "0.0.22"
  def basic(name_id_pwm, cmd_map, opts \\ [])

  def basic(%PulseWidth{} = pwm, %{name: name} = cmd, opts)
      when is_list(opts) do
    import TimeSupport, only: [utc_now: 0]
    import PulseWidth.Payload.Basic, only: [send_cmd: 4]

    # update the PulseWidth
    with {:ok, %PulseWidth{} = pwm} <- update(pwm, running_cmd: name),
         # add the command
         {:ok, %PulseWidth{} = pwm} <- add_cmd(pwm, utc_now()),
         # get the PulseWidthCmd inserted
         {:cmd, %PulseWidthCmd{refid: refid}} <- {:cmd, hd(pwm.cmds)},
         # send the command
         pub_rc <- send_cmd(pwm, refid, cmd, opts) do
      # assemble return value
      [basic: [name: name, pub_rc: pub_rc] ++ [opts]]
    else
      # just pass through any error encountered
      error -> {:error, error}
    end
  end

  def basic(x, %{name: _, basic: %{repeat: _, steps: _}} = cmd, opts)
      when is_list(opts) do
    with %PulseWidth{} = pwm <- find(x) do
      basic(pwm, cmd, opts)
    else
      nil -> {:not_found, x}
    end
  end

  @doc """
  Generate an example cmd payload using the first PulseWidth
  known to the system (sorted in ascending order).

  This function embeds documentation in the live system.

    ### Examples
      iex> PulseWidth.cmd_example(type, encode: true)
      Minimized JSON encoded Elixir native representation

      iex> PulseWidth.cmd_example(type, binary: true)
      Minimized JSON encoded binary representation

      iex> PulseWidth.cmd_example(type, bytes: true)
      Byte count of minimized JSON

      iex> PulseWidth.cmd_example(type, pack: true)
      Byte count of MsgPack encoding

      iex> PulseWidth.cmd_example(type, write: true)
      Appends pretty version of JSON encoded Sequence to
       ${HOME}/devel/helen/extra/json-snippets/basic.json

    ### Supported Types
      [:basic, :duty, :random]
  """

  @doc since: "0.0.14"
  def cmd_example(type \\ :random, opts \\ [])
      when is_atom(type) and is_list(opts) do
    name = names() |> hd()

    with %PulseWidth{name: _} = pwm <- find(name),
         cmd <- cmd_example_cmd(type, pwm) do
      cmd |> cmd_example_opts(opts)
    else
      error -> {:error, error}
    end
  end

  @doc """
    Creates the PulseWidth Command Example using %PulseWidth{} based on type

    NOTE:  This function is exposed publicly although, for a quick example,
           use cmd_example/2

      ### Supported Types
        [:duty, :basic, :random]

      ### Examples
        iex> PulseWidth.cmd_example_cmd(:random, %PulseWidth{})
  """

  @doc since: "0.0.22"
  def cmd_example_cmd(type, %PulseWidth{} = pwm) when is_atom(type) do
    alias PulseWidth.Payload.{Basic, Duty, Random}

    case type do
      :random -> Random.example(pwm)
      :basic -> Basic.example(pwm)
      :duty -> Duty.example(pwm)
      true -> %{}
    end
  end

  def cmd_example_file(%{pwm_cmd: cmd}) do
    cond do
      cmd == 0x10 -> "duty.json"
      cmd == 0x11 -> "basic.json"
      cmd == 0x12 -> "random.json"
      true -> "undefined.json"
    end
  end

  def cmd_example_opts(%{} = cmd, opts) do
    import Jason, only: [encode!: 2, encode_to_iodata!: 2]
    import Msgpax, only: [pack!: 1]

    cond do
      Keyword.has_key?(opts, :encode) ->
        Jason.encode!(cmd)

      Keyword.has_key?(opts, :binary) ->
        Jason.encode!(cmd, []) |> IO.puts()

      Keyword.has_key?(opts, :bytes) ->
        encode!(cmd, []) |> IO.puts() |> String.length()

      Keyword.has_key?(opts, :pack) ->
        [pack!(cmd)] |> IO.iodata_length()

      Keyword.has_key?(opts, :write) ->
        out = ["\n", encode_to_iodata!(cmd, pretty: true), "\n"]
        home = System.get_env("HOME")

        name = cmd_example_file(cmd)

        file =
          [
            home,
            "devel",
            "helen",
            "extra",
            "json-snippets",
            name
          ]
          |> Path.join()

        File.write(file, out, [:append])

      true ->
        cmd
    end
  end

  def delete_all(:dangerous) do
    import Ecto.Query, only: [from: 2]

    for pwm <- from(pwm in PulseWidth, select: [:id]) |> Repo.all() do
      Repo.delete(pwm)
    end
  end

  def duty(name, opts \\ [])

  def duty(name, opts) when is_binary(name) and is_list(opts) do
    duty = Keyword.get(opts, :duty, nil)

    with %PulseWidth{} = pwm <- find(name),
         {:duty_opt, true, pwm} <- {:duty_opt, is_number(duty), pwm},
         duty <- duty_calculate(pwm, duty) do
      duty(pwm, Keyword.put(opts, :duty, duty))
    else
      {:duty_opt, false, pwm} -> duty(pwm, opts)
      nil -> {:not_found, name}
    end
  end

  def duty(%PulseWidth{duty: curr_duty} = pwm, opts)
      when is_list(opts) do
    lazy = Keyword.get(opts, :lazy, true)
    duty = Keyword.get(opts, :duty, nil)

    # if the duty opt was passed then an update is requested
    with {:duty, {:opt, true}, _pwm} <-
           {:duty, {:opt, is_integer(duty)}, pwm},
         # the most typical scenario... lazy is true and current duty
         # does not match the requsted duty
         {:lazy, true, false, _pwm} <-
           {:lazy, lazy, duty == curr_duty, pwm} do
      # the requested duty does not match the current duty, update it
      duty_update([pwm: pwm, record_cmd: true] ++ opts)
    else
      {:duty, {:opt, false}, %PulseWidth{} = pwm} ->
        # duty change not included in opts, just return current duty
        duty_read([pwm: pwm] ++ opts)

      {:lazy, true, true, %PulseWidth{} = pwm} ->
        # requested lazy and requested duty matches current duty
        # nothing to do here... just return the duty
        duty_read([pwm: pwm] ++ opts)

      {:lazy, _lazy_or_not, _true_or_false, %PulseWidth{} = pwm} ->
        # regardless if lazy or not the current duty does not match
        # the requested duty, update it
        duty_update([pwm: pwm, record_cmd: true] ++ opts)
    end
  end

  def duty_calculate(%PulseWidth{duty_max: duty_max, duty_min: duty_min}, duty)
      when is_number(duty) do
    case duty do
      # floats less than zero are considered percentages
      d when is_float(d) and d <= 0.99 ->
        Float.round(duty_max * d, 0) |> trunc()

      # floats greate than zero are made integers
      d when is_float(d) and d > 0.99 ->
        Float.round(duty, 0) |> trunc()

      # bound limit duty requests
      d when d > duty_max ->
        duty_max

      d when d < duty_min ->
        duty_min

      duty ->
        duty
    end
  end

  @doc """
    Execute duty for a list of PulseWidth names that begin with a pattern

    Simply pipelines names_begin_with/1 and duty/2

      ## Examples
        iex> PulseWidth.duty_names_begin_with("front porch", duty: 256)
  """
  @doc since: "0.0.11"
  def duty_names_begin_with(pattern, opts)
      when is_binary(pattern) and is_list(opts) do
    for name <- names_begin_with(pattern), do: PulseWidth.duty(name, opts)
  end

  # when processing an external update the reading map will contain
  # the actual %PulseWidth{} struct when it has been found (already exists)
  # in this case perform the appropriate updates
  def external_update(
        %PulseWidth{} = pwm,
        %{
          duty: _duty,
          duty_max: _duty_max,
          duty_min: _duty_min,
          host: _host,
          mtime: mtime,
          msg_recv_dt: msg_recv_at
        } = r
      ) do
    import TimeSupport, only: [from_unix: 1]

    set =
      Enum.into(Map.take(r, keys(:create)), []) ++
        [last_seen_at: msg_recv_at, reading_at: from_unix(mtime)]

    update(pwm, set) |> PulseWidthCmd.ack_if_needed(r)
  end

  # when processing an external update and pulse_width is nil this is a
  # previously unknown %PulseWidth{}
  def external_update(nil, %{} = r) do
    add(r)
  end

  # this is the entry point for a raw incoming message before attempting to
  # find the matching %PulseWidth{} struct from the database
  def external_update(%{device: device} = r) do
    find_by_device(device) |> external_update(r)
  end

  def external_update(catchall) do
    Logger.warn([
      "external_update() unhandled msg: ",
      inspect(catchall, pretty: true)
    ])

    {:error, :unhandled_msg, catchall}
  end

  def find(id) when is_integer(id),
    do: Repo.get_by(__MODULE__, id: id)

  def find(name) when is_binary(name),
    do: Repo.get_by(__MODULE__, name: name)

  def find_by_device(device) when is_binary(device),
    do: Repo.get_by(__MODULE__, device: device)

  def like(string) when is_binary(string) do
    import Ecto.Query, only: [from: 2]

    like_string = ["%", string, "%"] |> IO.iodata_to_binary()

    from(p in PulseWidth, where: like(p.name, ^like_string), select: p.name)
    |> Repo.all()
  end

  @doc """
    Retrieve a list of Remote names
  """

  @doc since: "0.0.13"
  def names do
    import Ecto.Query, only: [from: 2]

    from(p in PulseWidth,
      order_by: p.name,
      select: p.name
    )
    |> Repo.all()
  end

  @doc """
    Retrieve a list of Remote names that begin with a pattern
  """

  @doc since: "0.0.11"
  def names_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(p in PulseWidth,
      where: like(p.name, ^like_string),
      order_by: p.name,
      select: p.name
    )
    |> Repo.all()
  end

  def off(list) when is_list(list) do
    for l <- list do
      off(l)
    end
  end

  def off(name) when is_binary(name) do
    with %PulseWidth{duty_min: min} <- find(name) do
      duty(name, duty: min)
    else
      _catchall -> {:not_found, name}
    end
  end

  def on(name) when is_binary(name) do
    with %PulseWidth{duty_max: max} <- find(name) do
      duty(name, duty: max)
    else
      _catchall -> {:not_found, name}
    end
  end

  def reload({:ok, %PulseWidth{id: id}}), do: reload(id)

  def reload(%PulseWidth{id: id}), do: reload(id)

  def reload(id) when is_number(id), do: Repo.get!(__MODULE__, id)

  def reload(catchall) do
    Logger.warn(["update() failed: ", inspect(catchall, pretty: true)])
    {:error, catchall}
  end

  def update(name, opts) when is_binary(name) and is_list(opts) do
    pwm = find(name)

    if is_nil(pwm), do: {:not_found, name}, else: update(pwm, opts)
  end

  def update(%PulseWidth{} = pwm, opts) when is_list(opts) do
    set = Keyword.take(opts, keys(:update)) |> Enum.into(%{})

    cs = changeset(pwm, set)

    if cs.valid?,
      do: {:ok, Repo.update(cs, stale_error_field: :stale_error) |> reload()},
      else: {:invalid_changes, cs}
  end

  defp changeset(pwm, params) when is_list(params),
    do: changeset(pwm, Enum.into(params, %{}))

  defp changeset(pwm, params) when is_map(params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3,
        unique_constraint: 3
      ]

    import Common.DB, only: [name_regex: 0]

    pwm
    |> cast(params, keys(:update))
    |> validate_required(keys(:required))
    |> validate_format(:name, name_regex())
    |> validate_number(:duty, greater_than_or_equal_to: 0)
    |> validate_number(:duty_min, greater_than_or_equal_to: 0)
    |> validate_number(:duty_max, greater_than_or_equal_to: 0)
    |> unique_constraint(:name, name: :pwm_name_index)
    |> unique_constraint(:device, name: :pwm_device_index)
  end

  defp duty_read(opts) do
    import TimeSupport, only: [ttl_expired?: 2]

    pwm = %PulseWidth{duty: duty, ttl_ms: ttl_ms} = Keyword.get(opts, :pwm)

    if ttl_expired?(last_seen_at(pwm), ttl_ms),
      do: {:ttl_expired, duty},
      else: {:ok, duty}
  end

  defp duty_update(opts) do
    pwm = %PulseWidth{} = Keyword.get(opts, :pwm)
    duty = Keyword.get(opts, :duty)

    {rc, pwm} = update(pwm, duty: duty)

    if rc == :ok do
      record_cmd(pwm, opts) |> duty_read()
    else
      {rc, pwm}
    end
  end

  defp last_seen_at(%PulseWidth{last_seen_at: x}), do: x

  defp record_cmd(%PulseWidth{} = pwm, opts) when is_list(opts) do
    import TimeSupport, only: [utc_now: 0]
    import PulseWidth.Payload.Duty, only: [send_cmd: 3]

    with {:ok, %PulseWidth{} = pwm} <- add_cmd(pwm, utc_now()),
         {:cmd, %PulseWidthCmd{refid: refid}} <- {:cmd, hd(pwm.cmds)},
         cmd_opts <- Keyword.take(opts, [:duty, :ack]),
         pub_rc <- send_cmd(pwm, refid, cmd_opts) do
      [pwm: pwm, pub_rc: pub_rc] ++ opts
    else
      error ->
        Logger.warn(["record_cmd() error: ", inspect(error, pretty: true)])
        {:error, error}
    end
  end

  # Keys For Updating, Creating a PulseWidth
  defp keys(:all),
    do:
      %PulseWidth{}
      |> Map.from_struct()
      |> Map.drop([:__meta__, :cmds])
      |> Map.keys()
      |> List.flatten()

  defp keys(:create) do
    drop = [:name]
    keys_refine(:update, drop)
  end

  defp keys(:required) do
    drop = [
      :reading_at,
      :description,
      :last_cmd_at,
      :last_seen_at,
      :discovered_at
    ]

    keys_refine(:update, drop)
  end

  defp keys(:update) do
    drop = [:id, :inserted_at, :updated_at]
    keys_refine(:all, drop)
  end

  defp keys_refine(base_keys, drop) do
    base = keys(base_keys) |> MapSet.new()
    remove = MapSet.new(drop)
    MapSet.difference(base, remove) |> MapSet.to_list()
  end
end
