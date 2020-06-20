defmodule Switch.DB.Alias do
  @moduledoc false

  require Logger
  use Ecto.Schema

  alias Switch.DB.Alias, as: Schema
  alias Switch.DB.Command, as: Command
  alias Switch.DB.Device, as: Device

  schema "switch_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:pio, :integer)
    field(:ttl_ms, :integer, default: 60_000)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id,
      define_field: false
    )

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
    Create a Switch alias to a device and specific pio
  """
  @doc since: "0.0.25"
  def create(%Device{id: id}, name, pio, opts \\ [])
      when is_binary(name) and is_integer(pio) and pio >= 0 and is_list(opts) do
    #
    # grab keys of interest for the schema (if they exist) and populate the
    # required parameters from the function call
    #
    Keyword.take(opts, [:description, :ttl_ms])
    |> Enum.into(%{})
    |> Map.merge(%{device_id: id, name: name, pio: pio, device_checked: true})
    |> upsert()
  end

  @doc """
    Delete a Switch Alias

      ## Examples
        iex> Switch.DB.Alias.delete("sample switch")

  """

  @doc since: "0.0.23"
  def delete(name_or_id) do
    with %Schema{} = x <- find(name_or_id),
         {:ok, %Schema{name: n}} <- Repo.delete(x) do
      {:ok, n}
    else
      error -> error
    end
  end

  @doc """
    Get a %Switch.DB.Alias{} by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Switch.DB.Alias{}

      ## Examples
        iex> Switch.DB.Alias.find("sample switch")
        %Switch.DB.Alias{}
  """

  @doc since: "0.0.21"
  def find(name_or_id) do
    check_args = fn
      x when is_binary(x) -> [name: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2, preload: 2]

    with opts when is_list(opts) <- check_args.(name_or_id),
         %Schema{} = found <- get_by(Schema, opts) do
      found |> preload([:device])
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  @doc """
    Retrieve Switch Alias names
  """
  @doc since: "0.0.22"
  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  @doc """
    Retrieve switch aliases names that begin with a pattern
  """

  @doc since: "0.0.22"
  def names_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(x in Schema,
      where: like(x.name, ^like_string),
      order_by: x.name,
      select: x.name
    )
    |> Repo.all()
  end

  @doc """
    Switch the device PIO for the Alias to true
  """
  @doc since: "0.0.22"
  def on(name_or_id, opts \\ []) when is_list(opts),
    do: position(name_or_id, [position: true] ++ opts)

  @doc """
    Switch the device PIO for the Alias to false

    extra options:
      :wait_for_pid      -> PID of process that is expected to terminate
      :check_interval_ms -> interval between checks if PID is alive
      :timeout_ms        -> max milliseconds to wait for PID to terminate
  """
  @doc since: "0.0.22"
  def off(name_id_or_list, opts \\ [])

  def off(name_list, opts) when is_list(name_list) and is_list(opts) do
    for s <- name_list, do: off(s, opts)
  end

  def off(name_or_id, opts) when is_list(opts) do
    pid = Keyword.get(opts, :wait_for_pid)
    check_interval_ms = Keyword.get(opts, :check_interval_ms, 10)
    max_checks = Keyword.get(opts, :timeout_ms, 1000) / check_interval_ms

    # if :pid_check_out isn't in the opts default to zero so the with
    # match is passed on the first check
    checks = Keyword.get(opts, :pid_check_count, 0)

    with {:pid_is_nil, false} <- {:pid_is_nil, is_nil(pid)},
         {:alive, true} <- {:alive, Process.alive?(pid)},
         {:checks, count} when count < max_checks <- {:checks, checks} do
      Process.sleep(check_interval_ms)

      # add (or increment) :pid_check_count and recurse
      opts = Keyword.update(opts, :pid_check_count, 1, fn x -> x + 1 end)
      off(name_or_id, opts)
    else
      {:checks, count} when count >= max_checks ->
        {:timeout, name_or_id}

      _anything ->
        # pid not in opts or pid already terminated

        # ensure we don't pass along any opts related to the pid check
        opts =
          Keyword.drop(opts, [
            :wait_for_pid,
            :check_interval_ms,
            :timeout_ms,
            :pid_check_count
          ])

        position(name_or_id, [position: false] ++ opts)
    end
  end

  @doc """
    Switch off the device aliases that begin with a pattern.

    See off/2 for available options that will be applied to all device aliases.
  """
  @doc since: "0.0.27"
  def off_names_begin_with(pattern, opts \\ [])
      when is_binary(pattern) and is_list(opts) do
    names_begin_with(pattern) |> off(opts)
  end

  def position(name, opts \\ [])

  def position(name, opts) when is_binary(name) and is_list(opts) do
    sa = find(name)

    if is_nil(sa), do: {:not_found, name}, else: position(sa, opts)
  end

  def position(%Schema{pio: pio, device: %Device{} = sd} = sa, opts)
      when is_list(opts) do
    lazy = opts[:lazy] || true
    position = opts[:position]
    cmd_map = %{pio: pio, state: position, initial_opts: opts}

    with {:ok, curr_position} <- Device.pio_state(sd, pio),
         # if the position opt was passed then an update is requested
         {:position, {:opt, true}} <-
           {:position, {:opt, is_boolean(position)}},

         # the most typical scenario... lazy is true and current position
         # does not match the requsted position
         {:lazy, true, false} <-
           {:lazy, lazy, position == curr_position} do
      # the requested position does not match the current posiion so
      # call Device.record_cmd/2 to publish the cmd to the host
      Device.record_cmd(sd, sa, cmd_map: cmd_map)
    else
      {:position, {:opt, false}} ->
        # position change not included in opts, just return current position
        Device.pio_state(sd, pio, opts)

      {:lazy, true, true} ->
        # requested lazy and requested position matches current position
        # nothing to do here... just return the position
        Device.pio_state(sd, pio, opts)

      {:lazy, _lazy_or_not, _true_or_false} ->
        # regardless if lazy or not the current position does not match
        # the requested position so change the position
        Device.record_cmd(sd, sa, cmd_map: cmd_map)

      {:ttl_expired, _pos} = rc ->
        rc

      catchall ->
        catchall
    end
    |> Command.ack_immediate_if_needed(opts)
  end

  def rename(%Schema{} = x, opts) when is_list(opts) do
    name = Keyword.get(opts, :name)

    changes =
      Keyword.take(opts, [
        :name,
        :description,
        :ttl_ms
      ])
      |> Enum.into(%{})

    with {:args, true} <- {:args, is_binary(name)},
         cs <- changeset(x, changes),
         {cs, true} <- {cs, cs.valid?},
         {:ok, sa} <- Repo.update(cs, returning: true) do
      {:ok, sa}
    else
      {:args, false} -> {:bad_args, opts}
      {%Ecto.Changeset{} = cs, false} -> {:invalid_changes, cs}
      error -> error
    end
  end

  @doc """
  Rename a switch alias

    Optional opts:
      description: <binary>   -- new description
      ttl_ms:      <integer>  -- new ttl_ms
  """
  @doc since: "0.0.23"
  def rename(name_or_id, name, opts \\ []) when is_list(opts) do
    # no need to guard name_or_id, find/1 handles it
    with %Schema{} = x <- find(name_or_id),
         {:ok, %Schema{name: n}} <- rename(x, name: name) do
      {:ok, n}
    else
      error -> error
    end
  end

  @doc """
  Toggle the device PIO for the alias on <-> off
  """
  @doc since: "0.0.22"
  def toggle(name_or_id, opts \\ []) do
    with {:ok, true} <- position(name_or_id) do
      position(name_or_id, [position: false] ++ opts)
    else
      {:ok, false} -> position(name_or_id, [position: true] ++ opts)
      error -> error
    end
  end

  def update(name_or_id, opts) when is_list(opts) do
    with %Schema{name: name} = x <- find(name_or_id) do
      rename(x, [name: name] ++ opts)
    else
      _not_found -> {:not_found, name_or_id}
    end
  end

  # upsert/1 confirms the minimum keys required and if the device to alias
  # exists
  def upsert(%{name: _, device_id: _, pio: _} = m) do
    upsert(%Schema{}, Map.put(m, :device_checked, true))
  end

  def upsert(catchall) do
    Logger.warn(["upsert/1 bad args: ", inspect(catchall, pretty: true)])
    {:bad_args, catchall}
  end

  # Alias.upsert/2 will update (or insert) a %Schema{} using the map passed
  def upsert(
        %Schema{} = x,
        %{device_checked: true, name: _, device_id: _, pio: _pio} = params
      ) do
    cs = changeset(x, Map.take(params, possible_changes()))

    replace_cols = [
      :description,
      :device_id,
      :pio,
      :ttl_ms,
      :updated_at
    ]

    with {:cs_valid, true} <- {:cs_valid, cs.valid?()},
         # the keys on_conflict: and conflict_target: indicate the insert
         # is an "upsert"
         {:ok, %Schema{id: _id} = x} <-
           Repo.insert(cs,
             on_conflict: {:replace, replace_cols},
             returning: true,
             conflict_target: [:name]
           ) do
      {:ok, x}
    else
      {:cs_valid, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        error
    end
    |> check_result(x, __ENV__)
  end

  def upsert(
        %Schema{},
        %{
          device_checked: false,
          name: _,
          device: device,
          device_id: _device_id,
          pio: pio
        }
      ),
      do: {:device_not_found, {device, pio}}

  #
  # PRIVATE
  #

  defp caller(%{function: {func, arity}}),
    do: [Atom.to_string(func), "/", Integer.to_string(arity)]

  defp changeset(x, params) when is_list(params) do
    changeset(x, Enum.into(params, %{}))
  end

  defp changeset(x, params) when is_map(params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3,
        unique_constraint: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, params, cast_changes())
    |> validate_required(possible_changes())
    |> validate_format(:name, name_regex())
    |> validate_number(:pio,
      greater_than_or_equal_to: 0
    )
    |> validate_number(:ttl_ms,
      greater_than_or_equal_to: 0
    )
    |> unique_constraint(:name, [:name])
  end

  defp check_result(res, x, env) do
    case res do
      # all is well, simply return the res
      {:ok, %Schema{}} ->
        true

      {:invalid_changes, cs} ->
        Logger.warn([
          caller(env),
          " invalid changes: ",
          inspect(cs, pretty: true)
        ])

      {:error, rc} ->
        Logger.warn([
          caller(env),
          " failed rc: ",
          inspect(rc, pretty: true),
          " for: ",
          inspect(x, pretty: true)
        ])

      true ->
        Logger.warn([
          caller(env),
          " error: ",
          inspect(res, pretty: true),
          " for: ",
          inspect(x, pretty: true)
        ])
    end

    res
  end

  #
  # Changeset Functions
  #

  #
  # Changeset Lists
  #

  defp cast_changes,
    do: [
      :name,
      :description,
      :device_id,
      :pio,
      :ttl_ms
    ]

  defp possible_changes,
    do: [
      :name,
      :description,
      :device_id,
      :pio,
      :ttl_ms
    ]
end
