defmodule PulseWidth.DB.Alias do
  @moduledoc """
  Database implementation of PulseWidth Aliases
  """

  use Ecto.Schema

  alias PulseWidth.DB.Alias, as: Schema
  alias PulseWidth.DB.{Command, Device}

  schema "pwm_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:capability, :string, default: "pwm")
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
    Create a PulseWidth alias to a device
  """
  @doc since: "0.0.25"
  def create(%Device{id: id}, name, opts \\ [])
      when is_binary(name) and is_list(opts) do
    #
    # grab keys of interest for the schema (if they exist) and populate the
    # required parameters from the function call
    #
    Keyword.take(opts, [:description, :capability, :ttl_ms])
    |> Enum.into(%{})
    |> Map.merge(%{device_id: id, name: name, device_checked: true})
    |> upsert()
  end

  @doc """
    Delete a PulseWidth Alias

      ## Examples
        iex> PulseWidth.DB.Alias.delete("sample pwm")

  """
  @doc since: "0.0.25"
  def delete(name_or_id) do
    with %Schema{} = x <- find(name_or_id),
         {:ok, %Schema{name: n}} <- Repo.delete(x) do
      {:ok, n}
    else
      error -> error
    end
  end

  def duty(name_or_id, opts \\ []) when is_list(opts) do
    lazy = opts[:lazy] || true
    duty = opts[:duty]

    # if the duty opt was passed then an update is requested
    with %Schema{device: %Device{} = d} = a <- find(name_or_id),
         # lazy_check does all the heavy lifting
         {:cmd_needed?, true, cmd_map} <- lazy_check(a, lazy, duty),
         cmd_map = Map.put(cmd_map, :initial_opts, opts) do
      Device.record_cmd(d, a, cmd_map: cmd_map)
    else
      nil ->
        {:not_found, name_or_id}

      # lazy_check determined should only return the current value
      {:cmd_needed?, false, dev_alias} ->
        duty_now(dev_alias, opts)
    end
    |> Command.ack_immediate_if_needed(opts)
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
    for name <- names_begin_with(pattern), do: duty(name, opts)
  end

  @doc """
    Get a %PulseWidth.DB.Alias{} by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %PulseWidth.DB.Alias{}

      ## Examples
        iex> PulseWidth.DB.Alias.find("sample pwm")
        %PulseWidth.DB.Alias{}
  """

  @doc since: "0.0.25"
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
    Retrieve PulseWidth Alias names
  """
  @doc since: "0.0.25"
  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  @doc """
    Retrieve pwm aliases names that begin with a pattern
  """

  @doc since: "0.0.25"
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

  def off(list) when is_list(list) do
    for l <- list do
      off(l)
    end
  end

  def off(name) when is_binary(name) do
    with %Device{duty_min: min} <- find(name) do
      duty(name, duty: min)
    else
      _catchall -> {:not_found, name}
    end
  end

  def on(name) when is_binary(name) do
    with %Device{duty_max: max} <- find(name) do
      duty(name, duty: max)
    else
      _catchall -> {:not_found, name}
    end
  end

  def rename(%Schema{} = x, opts) when is_list(opts) do
    name = Keyword.get(opts, :name)

    changes =
      Keyword.take(opts, [
        :name,
        :description,
        :capability,
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
  Rename a pwm alias

    Optional opts:
      description: <binary>         -- new description
      ttl_ms:      <integer>        -- new ttl_ms
      capability:  "pwm" | "toggle" -- support pwm (duty) or on/off only
  """
  @doc since: "0.0.25"
  def rename(name_or_id, name, opts \\ []) when is_list(opts) do
    # no need to guard name_or_id, find/1 handles it
    with %Schema{} = x <- find(name_or_id),
         {:ok, %Schema{name: n}} <- rename(x, name: name) do
      {:ok, n}
    else
      error -> error
    end
  end

  # upsert/1 confirms the minimum keys required and if the device to alias
  # exists
  def upsert(%{name: _, device_id: _} = m) do
    upsert(%Schema{}, Map.put(m, :device_checked, true))
  end

  def upsert(catchall) do
    {:bad_args, catchall}
  end

  # Alias.upsert/2 will update (or insert) a %Schema{} using the map passed
  def upsert(
        %Schema{} = x,
        %{device_checked: true, name: _, device_id: _} = params
      ) do
    cs = changeset(x, Map.take(params, keys(:all)))

    with {:cs_valid, true} <- {:cs_valid, cs.valid?()},
         # the keys on_conflict: and conflict_target: indicate the insert
         # is an "upsert"
         {:ok, %Schema{id: _id} = x} <-
           Repo.insert(cs,
             on_conflict: {:replace, keys(:replace)},
             returning: true,
             conflict_target: [:name]
           ) do
      {:ok, x}
    else
      {:cs_valid, false} -> {:invalid_changes, cs}
      {:error, rc} -> {:error, rc}
      error -> {:error, error}
    end
  end

  def upsert(%Schema{}, %{device_checked: false, device: d}),
    do: {:device_not_found, d}

  ##
  ## PRIVATE
  ##

  defp changeset(x, p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3,
        validate_inclusion: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, Enum.into(p, %{}), keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:name, name_regex())
    |> validate_number(:ttl_ms, greater_than_or_equal_to: 0)
    |> validate_inclusion(:capability, ["pwm", "toggle"])
  end

  defp duty_calculate(%_{duty_max: max, duty_min: min}, duty) do
    percent = fn x -> Float.round(max * x, 0) |> trunc() end
    round = fn x -> Float.round(x, 0) |> trunc() end

    case duty do
      # duty was not in the original opts
      nil -> nil
      # floats less than one are considered percentages
      d when is_float(d) and d <= 0.99 -> percent.(d)
      # floats greater than one are made integers
      d when is_float(d) and d > 0.99 -> round.(d)
      # bound limit duty requests
      d when d > max -> max
      d when d < min -> min
      # it's just a simple duty > 1, less than max and greater than min
      duty -> duty
    end
  end

  defp duty_now(%_{ttl_ms: ttl_ms, device: %_{duty: duty} = x}, opts) do
    import TimeSupport, only: [ttl_expired?: 2]

    if ttl_expired?(last_seen_at(x), opts[:ttl_ms] || ttl_ms),
      do: {:ttl_expired, duty},
      else: {:ok, duty}
  end

  # Keys For Updating, Creating a PulseWidth
  defp keys(:all) do
    alias Schema, as: S

    drop =
      [:__meta__, S.__schema__(:associations), S.__schema__(:primary_key)]
      |> List.flatten()

    %Schema{}
    |> Map.from_struct()
    |> Map.drop(drop)
    |> Map.keys()
    |> List.flatten()
  end

  defp keys(:cast), do: keys(:all)
  defp keys(:required), do: [:name]
  defp keys(:replace), do: keys_drop(:all, [:name])

  defp keys_drop(base_keys, drop) do
    base = keys(base_keys) |> MapSet.new()
    remove = MapSet.new(drop)
    MapSet.difference(base, remove) |> MapSet.to_list()
  end

  defp last_seen_at(%Device{last_seen_at: x}), do: x

  defp lazy_check(%_{device: %_{duty: d} = device} = dev_alias, lazy, duty) do
    new_duty = duty_calculate(device, duty)

    cond do
      # duty was not in the opts, this is a read
      is_nil(new_duty) -> {:cmd_needed?, false, dev_alias}
      # lazy requested and current duty == new duty
      lazy == true and d == new_duty -> {:cmd_needed?, false, dev_alias}
      # no match above means we need to send a cmd
      true -> {:cmd_needed?, true, %{duty: duty}}
    end
  end
end
