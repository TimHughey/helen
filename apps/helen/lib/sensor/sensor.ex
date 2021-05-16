defmodule Sensor do
  @moduledoc """

  Public API for Sensors
    a. Devices
    b. Datapoints
    c. Aliases

    * handling of messages received via MQTT
    * querying for datapoint values
  """

  require Logger

  alias Sensor.DB.{Alias, Device}
  alias Sensor.{Msg, Status}

  @behaviour Alfred.Immutable

  def alias_create(device_or_id, name, opts \\ []) do
    {device_opts, alias_opts} = Keyword.split(opts, [:device_stale_after])

    txn_res =
      Repo.checkout(fn ->
        Repo.transaction(fn ->
          # 1. ensure the name is not already knowbn
          # 2. ensure the device exists
          # 3. ensure the alias does not exist
          with {:alfred, :available, ^name} <- Alfred.available(name),
               {:device, %Device{} = d} <- Device.find_check_stale(device_or_id, device_opts),
               {:alias, nil} <- {:alias, Alias.find(name)},
               {:ok, %Alias{} = a} <- Alias.create(d, name, alias_opts) do
            {:created, [name: a.name, device: Alias.device_name(a)]}
          else
            {:alfred, :taken, x} -> {:exists, [name: x.name, alfred: x]}
            {:alias, %Alias{} = a} -> {:exists, [name: a.name, device: Alias.device_name(a)]}
            {:device, nil} -> {:not_found, [device: device_or_id]}
            {:device_stale, res} -> {:device_stale, res}
            error -> error
          end

          # txn end
        end)

        # checkout end
      end)

    case txn_res do
      {:ok, res} -> res
      db_error -> db_error
    end
  end

  defdelegate alias_find(name_or_id), to: Alias, as: :find

  # @doc """
  # Alias the most recently inserted device
  # """
  # @doc since: "0.0.27"
  # def alias_most_recent(name) do
  #   case unaliased_recent() |> hd() do
  #     {device, _inserted_at} -> alias_create(device, name)
  #     [] -> {:no_unaliased_devices}
  #     rc -> rc
  #   end
  # end

  # @doc """
  # See unaliased/0
  # """
  # @doc since: "0.0.27"
  # def available, do: unaliased()

  # @doc """
  # See unaliased_recent
  # """
  # @doc since: "0.0.27"
  # def available_recent, do: unaliased_recent()

  @doc """
    Public API for deleting a Sensor Alias

    Deletes the database record and prune (deletes) from Alfred within a checked out transaction.

    All Datapoints related to the Sensor Alias are also deleted in small batches to limit impact
    to database.
  """
  @doc since: "0.9.8"
  def delete(name_or_id) do
    txn_res =
      Repo.checkout(fn ->
        Repo.transaction(fn ->
          # 1. delete from DB
          # 2. delete from Alfred
          with {:ok, delete_res} <- Alias.delete(name_or_id),
               {:ok, _} <- Alfred.delete(get_in(delete_res, [:name])) do
            {:ok, delete_res}
          else
            # DB delete succeeded, Alfred didn't know the name -- inform caller but consider success
            {:ok, [alfred: :unknown, name: _] = res} -> {:ok, [db: :ok] ++ res}
            db_unknown_or_error -> db_unknown_or_error
          end

          # txn end
        end)

        # checkout end
      end)

    case txn_res do
      {:ok, res} -> res
      db_error -> db_error
    end
  end

  @doc """
    Public API for retrieving a list of Sensor Device names
  """
  @doc since: "0.0.19"
  def devices do
    Device.devices_begin_with("")
  end

  defdelegate device_find(device_or_id), to: Device, as: :find
  defdelegate devices_begin_with(pattern \\ ""), to: Device

  @impl true
  defdelegate exists?(name), to: Alias

  def handle_message(msg_in) do
    Logger.debug(["\n", inspect(msg_in, pretty: true), "\n"])

    msg_in |> put_in([:msg_handler], __MODULE__) |> Msg.handle() |> Alfred.just_saw()
  end

  # @doc """
  # Deletes devices that were last updated before UTC now shifted backward by opts.
  #
  # Returns a list of the deleted devices.
  #
  # ## Examples
  #
  #     iex> Sensor.delete_unavailable([days: 7])
  #     ["dead_device1", "dead_device2"]
  #
  # """
  # @doc since: "0.0.27"
  # defdelegate delete_unavailable(opts), to: Device

  @doc """
    Public API for retrieving a list of Sensor Alias names
  """
  @doc since: "0.0.19"
  defdelegate names, to: Alias

  @doc """
    Public API for retrieving Sensor Alias names that begin with a patteen
  """
  @doc since: "0.0.19"
  def names_begin_with(pattern) when is_binary(pattern) do
    Alias.names_begin_with(pattern)
  end

  # @doc """
  #   Public API for renaming a Sensor Alias
  # """
  # @doc since: "0.0.23"
  # def rename(name_or_id, new_name, opts \\ []) do
  #   Alias.rename(name_or_id, new_name, opts)
  # end
  #
  # @doc """
  #   Public API for assigning a Sensor Alias to a different Device
  # """
  # @doc since: "0.0.27"
  # def replace(name_or_id, new_dev_name_or_id) do
  #   Alias.replace(name_or_id, new_dev_name_or_id)
  # end
  #
  # @doc """
  # Replace the existing Alias with the most recently inserted device
  # """
  # @doc since: "0.0.27"
  # def replace_with_most_recent(name) do
  #   case unaliased_recent() |> hd() do
  #     {device, _inserted_at} -> replace(name, device)
  #     [] -> {:no_unaliased_devices}
  #     rc -> rc
  #   end
  # end

  # @doc """
  # Returns the fahrenheit temperature for a Sensor by alias
  # """
  # @doc since: "0.0.19"
  # def fahrenheit(sensor_alias, opts \\ [])
  #     when is_binary(sensor_alias) and is_list(opts) do
  #   with %Alias{device: dev} <- Alias.find(sensor_alias),
  #        %Device{datapoints: dp} <- Device.load_datapoints(dev, opts),
  #        val when is_number(val) <- DataPoint.avg_of(dp, :temp_f) do
  #     val
  #   else
  #     _error -> nil
  #   end
  # end
  #
  # @doc """
  # Returns the relative humidity for a Sensor by alias
  # """
  # @doc since: "0.0.19"
  # def relhum(sensor_alias, opts \\ [])
  #     when is_binary(sensor_alias) and is_list(opts) do
  #   with %Alias{device: dev} <- Alias.find(sensor_alias),
  #        %Device{datapoints: dp} <- Device.load_datapoints(dev, opts),
  #        val when is_number(val) <- DataPoint.avg_of(dp, :relhum) do
  #     val
  #   else
  #     _error -> nil
  #   end
  # end
  #
  # @doc """
  # Return a list of devices that are not aliased ordered by inserted at desc
  # """
  # @doc since: "0.0.27"
  # defdelegate unaliased, to: Device
  #
  # @doc """
  # Return the first five devices that are not aliased order by inserted at desc
  # """
  # @doc since: "0.0.27"
  # def unaliased_recent do
  #   unaliased() |> Enum.take(5)
  # end

  # @doc """
  # Selects devices that were last updated before UTC now shifted backward by opts.
  #
  # Returns a list of devices.
  #
  # ## Examples
  #
  #     iex> Sensor.unavailable([days: 7])
  #     ["dead_device1", "dead_device2"]
  #
  # """
  # @doc since: "0.0.27"
  # def unavailable(opts), do: Device.unavailable(opts)

  @impl true
  def status(name_or_id, opts \\ []) when is_list(opts) do
    case Alias.find(name_or_id) do
      %Alias{} = a -> Status.make_status(a, opts)
      other -> other
    end
  end
end
