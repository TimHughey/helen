defmodule Remote do
  @moduledoc """
  The Remote module proveides the mapping from a Remote Device (aka MCR) hostname to
  a defined name and records various metadata about the remote device.
  """

  require Logger

  def browse do
    import Remote.DB.Remote, only: [all: 0]

    sorted = all() |> Enum.sort(fn a, b -> a.name <= b.name end)
    Scribe.console(sorted, data: [:id, :name, :host, :hw, :inserted_at])
  end

  @doc """
    Handles all aspects of processing Remote messages of "remote" type
    (periodic updates)

     - if the message hasn't been processed, then attempt to
  """
  @doc since: "0.0.16"
  def handle_message(%{processed: false, type: type} = msg_in)
      when type in ["remote", "boot"] do
    alias Remote.Schemas.Remote, as: Schema
    alias Remote.DB.Remote, as: DB
    alias Fact.Influx

    # the with begins with processing the message through Device.DB.upsert/1
    with %{remote_host: remote_host} = msg <- DB.upsert(msg_in),
         # was the upset a success?
         {:ok, %Schema{}} <- remote_host,
         msg <- Map.put(msg, :processed, true),
         msg <- send_profile_if_needed(msg),
         msg <- log_boot_if_needed(msg),
         # now send the augmented message to the timeseries database
         msg <- Influx.handle_message(msg),
         write_rc <- Map.get(msg, :write_rc),
         {msg, {:processed, :ok}} <- {msg, write_rc} do
      msg
    else
      # we didn't match when attempting to write the timeseries metric
      # this isn't technically a failure however we do want to signal to
      # the caller something is amiss
      {msg, {:processed, :no_match} = write_rc} ->
        ["no match: ", inspect(msg, pretty: true)] |> IO.puts()

        Map.merge(msg, %{
          processed: true,
          warning: :remote_host_warning,
          remote_host_warning: write_rc
        })

      error ->
        Map.merge(msg_in, %{
          processed: true,
          fault: :remote_host_fault,
          remote_host_fault: error
        })
    end
  end

  # if the primary handle_message does not match then simply return the msg
  # since it wasn't for sensor and/or has already been processed in the
  # pipeline
  def handle_message(%{} = msg_in), do: msg_in

  @doc """
    Request OTA updates based on a prefix pattern

    Simply pipelines names_begin_with/1 and ota_update/2

      ## Examples
        iex> Schema.ota_names_begin_with("lab-", [])
  """
  @doc since: "0.0.11"
  def ota(pattern, opts \\ []) when is_binary(pattern) do
    import Remote.DB.Remote, only: [names_begin_with: 1]

    names_begin_with(pattern) |> ota_update(opts)
  end

  ###
  ###
  ### SPECIAL CASE FOR EASE OF OPERATIONS
  ###
  ###

  def ota_roost, do: "roost-" |> ota()
  def ota_lab, do: "lab-" |> ota()
  def ota_reef, do: "reef-" |> ota()
  def ota_test, do: "test-" |> ota()
  def ota_all, do: ["roost-", "lab-", "reef-", "test-"] |> ota()

  defdelegate profile_create(name, opts \\ []),
    to: Remote.DB.Profile,
    as: :create

  defdelegate profile_duplicate(name, new_name),
    to: Remote.DB.Profile,
    as: :duplicate

  defdelegate profile_find(name_or_id), to: Remote.DB.Profile, as: :find
  defdelegate profile_reload(varies), to: Remote.DB.Profile, as: :reload
  defdelegate profile_names, to: Remote.DB.Profile, as: :names

  defdelegate profile_to_external_map(name),
    to: Remote.DB.Profile,
    as: :to_external_map

  defdelegate profile_update(name_or_schema, opts),
    to: Remote.DB.Profile,
    as: :update

  defdelegate profile_lookup_key(key), to: Remote.DB.Profile, as: :lookup_key

  def restart(what, opts \\ []) do
    import Remote.DB.Remote, only: [remote_list: 1]

    opts = Keyword.put_new(opts, :log, false)
    restart_list = remote_list(what) |> Enum.filter(fn x -> is_map(x) end)

    if Enum.empty?(restart_list) do
      {:failed, restart_list}
    else
      opts = opts ++ [restart_list: restart_list]
      OTA.restart(opts)
    end
  end

  #
  # PRIVATE FUNCTIONS
  #

  defp ota_update(what, opts) do
    import Remote.DB.Remote, only: [remote_list: 1]

    opts = Keyword.put_new(opts, :log, false)
    update_list = remote_list(what) |> Enum.filter(fn x -> is_map(x) end)

    if Enum.empty?(update_list) do
      []
    else
      opts = opts ++ [update_list: update_list]
      OTA.send_cmd(opts)
    end
  end

  defp send_profile_if_needed(%{type: type, remote_host: remote_host} = msg) do
    import Mqtt.Command.Remote.Profile, only: [send_cmd: 1]
    # alias Fact.Remote.Boot
    alias Remote.Schemas.Remote, as: Schema

    with {:ok, %Schema{name: _name} = rem} <- remote_host,
         "boot" <- type do
      send_cmd(rem)

      # Boot.record(host: name, vsn: vsn)

      msg
    else
      _error -> msg
    end
  end

  defp log_boot_if_needed(
         %{
           type: "boot",
           firmware_vsn: vsn,
           reset_reason: reset,
           heap_free: heap_free,
           heap_min: heap_min,
           batt_mv: batt_mv,
           ap_rssi: ap_rssi,
           remote_host: remote_host
         } = msg
       ) do
    alias Remote.Schemas.Remote, as: Schema
    log = Map.get(msg, :log, true)

    with {:ok, %Schema{name: name}} <- remote_host,
         true <- log do
      heap_free = (heap_free / 1024) |> Float.round(1) |> Float.to_string()
      heap_min = (heap_min / 1024) |> Float.round(1) |> Float.to_string()

      heap = ["heap(", heap_min, "k,", heap_free, "k)"] |> IO.iodata_to_binary()
      ap_db = [Integer.to_string(ap_rssi), "dB"] |> IO.iodata_to_binary()
      batt_mv = [Float.to_string(batt_mv), "mV"] |> IO.iodata_to_binary()

      [name, "BOOT", reset, vsn, ap_db, batt_mv, heap]
      |> Enum.join(" ")
      |> Logger.info()
    else
      _ -> nil
    end

    msg
  end

  defp log_boot_if_needed(%{host: host, reset_reason: _reason} = msg) do
    ["BOOT message from host=\"", host, "\" did not match"]
    |> Logger.warn()

    msg
  end

  defp log_boot_if_needed(msg), do: msg
end
