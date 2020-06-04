defmodule Remote do
  @moduledoc """
  The Remote module proveides the mapping from a Remote Device (aka MCR) hostname to
  a defined name and records various metadata about the remote device.
  """

  require Logger

  alias Remote.DB
  alias Remote.Schemas

  def browse do
    alias Schemas.Remote, as: Schema

    sorted = Repo.all(Schema) |> Enum.sort(fn a, b -> a.name <= b.name end)

    Scribe.console(sorted, data: [:id, :name, :host, :inserted_at])
  end

  @doc """
    Delete a Remote by name, id or (as a last resort) host
  """

  @doc since: "0.0.21"
  defdelegate delete(name_id_host), to: DB.Remote

  @doc """
    Deprecate a Remote by renaming to "~ name-time"
  """

  @doc since: "0.0.21"
  defdelegate deprecate(name_id_host), to: DB.Remote

  @doc """
    Get a Remmote by id, name or (as a last resort) host

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Remote.Schemas.Remote{}

      ## Examples
        iex> Remote.DB.Remote.find("test-builder")
        %Remote.Schemas.Remote{}
  """

  @doc since: "0.0.21"
  defdelegate find(name_or_id), to: DB.Remote

  @doc """
    Handles all aspects of processing Remote messages of "remote" type
    (periodic updates)

     - if the message hasn't been processed, then attempt to
  """
  @doc since: "0.0.16"
  def handle_message(%{processed: false, type: type} = msg_in)
      when type in ["remote", "boot"] do
    alias Schemas.Remote, as: Schema
    alias DB.Remote, as: DB
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
    Retrieve all Remote names
  """

  @doc since: "0.0.21"
  defdelegate names, to: DB.Remote

  @doc """
    Retrieve a list of Remote names that begin with a pattern
  """

  @doc since: "0.0.21"
  defdelegate names_begin_with(pattern), to: DB.Remote

  @doc """
    Request OTA updates based on a name pattern

    If opts is empty then the configuration from the app env is used
    to build the uri of the firmware.

    Possible Opts:
      :host -> host to make the https request to
      :path -> path name to the firmware file
      :file -> actual firmware file name
  """
  @doc since: "0.0.21"
  def ota(name_pattern, opts \\ []) do
    with remotes when is_list(remotes) <- names_begin_with(name_pattern),
         false <- Enum.empty?(remotes),
         # ota commands must include the uri of the firmware in the payload
         ota_cmd_map <- ota_uri_build(opts) do
      remote_send_cmds(remotes, "ota", ota_cmd_map)
    else
      _not_found -> {:not_found, name_pattern}
    end
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

  @doc """
    Set the profile for a Remote
  """
  @doc since: "0.0.20"
  defdelegate profile_assign(name_or_id, profile_name), to: DB.Remote

  defdelegate profile_create(name, opts \\ []),
    to: DB.Profile,
    as: :create

  defdelegate profile_duplicate(name, new_name),
    to: DB.Profile,
    as: :duplicate

  defdelegate profile_find(name_or_id), to: DB.Profile, as: :find
  defdelegate profile_reload(varies), to: DB.Profile, as: :reload
  defdelegate profile_names, to: DB.Profile, as: :names

  @doc """
    Output the Profile Payload for a Remote
  """
  @doc since: "0.0.21"
  def profile_payload_puts(name_or_id) do
    alias Schemas.Profile, as: Profile
    alias Schemas.Remote, as: Remote

    with %Remote{profile: pname} = rem <- find(name_or_id),
         # find the profile assigned to this remote
         {:pfile, %Profile{} = profile} <- {:pfile, profile_find(pname)},
         # create the payload using the remote and profile
         cmd <- Profile.create_profile_payload(rem, profile) do
      ["\n", "payload = ", inspect(cmd, pretty: true), "\n"]
      |> IO.puts()
    else
      _error -> {:not_found, name_or_id}
    end
  end

  defdelegate profile_to_external_map(name),
    to: DB.Profile,
    as: :to_external_map

  defdelegate profile_update(name_or_schema, opts),
    to: DB.Profile,
    as: :update

  defdelegate profile_lookup_key(key), to: DB.Profile, as: :lookup_key

  @doc """
    Rename a Remote

    NOTE: the remote to rename is found by id, name or host
  """

  @doc since: "0.0.21"
  defdelegate rename(existing_name_id_host, new_name), to: DB.Remote

  @doc """
    Issue a restart request to a single or list of Remotes
  """

  @doc since: "0.0.21"
  def restart(name_pattern) do
    with remotes when is_list(remotes) <- names_begin_with(name_pattern),
         false <- Enum.empty?(remotes) do
      # restart commands are trivial, they only require the base cmd info
      # which is provided by remote_send_cmds/2
      remote_send_cmds(remotes, "restart")
    else
      _not_found -> {:not_found, name_pattern}
    end
  end

  @doc """
    Rename and restart a Remote

    NOTE:  To effectuate the new name the Remote must be restarted.
  """

  def rename_and_restart(name_id_host, new_name) do
    alias DB.Remote, as: DB

    # rename/2 will return a list upon success
    with res when is_list(res) <- DB.rename(name_id_host, new_name),
         remote_key <- Keyword.get(res, :remote),
         new_name <- Keyword.get(remote_key, :now_named),
         restart_res <- restart(new_name) do
      Keyword.put(res, :restart, restart_res)
    else
      error -> error
    end
  end

  #
  # PRIVATE FUNCTIONS
  #

  defp ota_uri_build(opts) when is_list(opts) do
    # filter down the opts supplied to only those of interest
    opts = Keyword.take(opts, [:host, :path, :file])

    # add any required opts that were not provided
    final_uri_opts = Keyword.merge(ota_uri_default_opts(), opts)

    # return a map that will be used as additional payload for the command
    %{
      uri:
        [
          "https:/",
          Keyword.get(final_uri_opts, :host),
          Keyword.get(final_uri_opts, :path),
          Keyword.get(final_uri_opts, :file)
        ]
        |> Enum.join("/")
    }
  end

  defp ota_uri_default_opts do
    Application.get_env(:helen, OTA,
      uri: [
        host: "localhost",
        path: "example_path",
        file: "example.bin"
      ]
    )
    |> Keyword.get(:uri)
  end

  defp remote_send_cmds(remotes, cmd, payload \\ %{})

  defp remote_send_cmds(remotes, cmd, %{} = payload) when is_list(remotes) do
    alias Schemas.Remote, as: Schema
    alias DB.Remote, as: DB

    for x <- remotes do
      with %Schema{} = found <- DB.find(x) do
        remote_send_cmds(found, cmd, payload)
      else
        _not_found -> {:not_found, x}
      end
    end
    |> List.flatten()
  end

  defp remote_send_cmds(
         %Schemas.Remote{name: name, host: host},
         cmd,
         %{} = payload
       )
       when cmd in ["restart", "ota"] do
    import Mqtt.Client, only: [publish_to_host: 2]
    import TimeSupport, only: [unix_now: 0]

    # all commands must include the basic information
    base_cmd = %{name: name, host: host, mtime: unix_now()}

    # merge in (or override) the command base with the payload (if any)
    #
    # for example, restart commands only require the basic command info
    # where, on the other hand, ota updates must supply additional information
    cmd_map = Map.merge(base_cmd, payload)
    {rc, ref} = publish_to_host(cmd_map, cmd)

    # return [cmd: [{name, rc, ref}]]
    [{String.to_atom(cmd), {name, rc, ref}}]
  end

  defp send_profile_if_needed(%{type: type, remote_host: remote_host} = msg) do
    import Mqtt.Client, only: [publish_to_host: 2]
    alias Schemas.Remote, as: Schema
    alias Schemas.Profile, as: Profile

    with {:ok, %Schema{name: _name, profile: pname} = rem} <- remote_host,
         "boot" <- type,
         # find the profile assigned to this remote
         {:pfile, %Profile{} = profile} <- {:pfile, profile_find(pname)},
         # create the payload using the remote and profile
         cmd <- Profile.create_profile_payload(rem, profile) do
      [inspect(cmd, pretty: true)] |> IO.puts()
      {rc, ref} = publish_to_host(cmd, "profile")

      Map.put(msg, :remote_profile_send, {rc, ref})
    else
      {:pfile, nil} ->
        Map.put(msg, :remote_profile_send, {:failed, :not_found})

      error ->
        Map.put(msg, :remote_profile_send, {:failed, error})
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
    alias Schemas.Remote, as: Schema
    log = Map.get(msg, :log, true)

    with {:ok, %Schema{name: name}} <- remote_host,
         true <- log do
      heap_free = (heap_free / 1024) |> Float.round(1) |> Float.to_string()
      heap_min = (heap_min / 1024) |> Float.round(1) |> Float.to_string()

      heap = ["heap(", heap_min, "k,", heap_free, "k)"] |> IO.iodata_to_binary()
      ap_db = [Integer.to_string(ap_rssi), "dB"] |> IO.iodata_to_binary()
      batt_mv = [Integer.to_string(batt_mv), "mV"] |> IO.iodata_to_binary()

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
