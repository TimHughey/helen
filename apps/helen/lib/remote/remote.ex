defmodule Remote do
  @moduledoc """
  The Remote module proveides the mapping from a Remote Device (aka MCR) hostname to
  a defined name and records various metadata about the remote device.
  """

  require Logger

  alias Remote.DB
  alias Remote.DB.Profile
  alias Remote.DB.Remote, as: Schema

  def browse do
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
  def ota(_name_pattern, _opts \\ []), do: nil

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
    Adjust an existing profile by add/subtracting the values specified to
    the existing profile values.

    ## Examples
      iex> Remote.profile_adjust("test-builder", [i2c_core_stack: -1024])
  """
  @doc since: "0.0.29"
  def profile_adjust(profile_name, adjustments) when is_list(adjustments) do
    case profile_find(profile_name) do
      %Profile{} = profile ->
        changes =
          for {k, v} when is_atom(k) <- adjustments, reduce: [] do
            acc ->
              case get_in(Map.from_struct(profile), [k]) do
                nil -> acc
                val when is_integer(val) -> put_in(acc, [k], val + v)
                val when is_boolean(val) -> put_in(acc, [k], val)
                _no_match -> acc
              end
          end

        profile_update(profile_name, changes)

      nil ->
        {:not_found, profile_name}
    end
  end

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

  defdelegate profile_to_external_map(name),
    to: DB.Profile,
    as: :to_external_map

  defdelegate profile_update(name_or_schema, opts),
    to: DB.Profile,
    as: :update

  defdelegate profile_lookup_key(key), to: DB.Profile, as: :lookup_key

  @doc """
  Send an unstructured raw text command to a single Remote
  """

  @doc since: "0.0.29"
  def raw(_name_id_host, _raw), do: nil

  @doc """
    Rename a Remote

    NOTE: the remote to rename is found by id, name or host
  """

  @doc since: "0.0.21"
  defdelegate rename(existing_name_id_host, new_name), to: DB.Remote

  @doc """
    Issue a restart command to the Remotes that match the specified pattern
  """
  @doc since: "0.0.21"
  def restart(_name_pattern), do: nil

  @doc """
    Rename and restart a Remote

    NOTE:  To effectuate the new name the Remote must be restarted.
  """

  def rename_and_restart(name_id_host, new_name) do
    # rename/2 will return a list upon success
    with res when is_list(res) <- Schema.rename(name_id_host, new_name),
         remote_key <- Keyword.get(res, :remote),
         new_name <- Keyword.get(remote_key, :now_named),
         restart_res <- restart(new_name) do
      Keyword.put(res, :restart, restart_res)
    else
      error -> error
    end
  end

  @doc """
  Transmit a payload to a Remote.

  The payload is merged into the generated base map and transmitted to the
  Remote specificed.  The subtopic specified is transmitted as-is.
  """
  @doc since: "0.0.29"
  def tx_payload(_name_or_id, _subtopic, _payload), do: nil

  #
  # PRIVATE FUNCTIONS
  #

  # defp ota_uri_build(opts) when is_list(opts) do
  #   # filter down the opts supplied to only those of interest
  #   opts = Keyword.take(opts, [:host, :path, :file])
  #
  #   # add any required opts that were not provided
  #   final_uri_opts = Keyword.merge(ota_uri_default_opts(), opts)
  #
  #   # return a map that will be used as additional payload for the command
  #   %{
  #     uri:
  #       [
  #         "https:/",
  #         Keyword.get(final_uri_opts, :host),
  #         Keyword.get(final_uri_opts, :path),
  #         Keyword.get(final_uri_opts, :file)
  #       ]
  #       |> Enum.join("/")
  #   }
  # end
  #
  # defp ota_uri_default_opts do
  #   Application.get_env(:helen, OTA,
  #     uri: [
  #       host: "localhost",
  #       path: "example_path",
  #       file: "example.bin"
  #     ]
  #   )
  #   |> Keyword.get(:uri)
  # end

  # defp send_profile_if_needed(%{type: type, remote_host: remote_host} = msg) do
  #   with {:ok, %Schema{name: _name, profile: pname} = rem} <- remote_host,
  #        "boot" <- type,
  #        # find the profile assigned to this remote
  #        {:pfile, %Profile{} = profile} <- {:pfile, profile_find(pname)},
  #        # create the payload using the remote and profile
  #        cmd <- Profile.create_profile_payload(rem, profile) do
  #     {rc, ref} = {nil, nil}
  #
  #     Map.put(msg, :remote_profile_send, {rc, ref})
  #   else
  #     {:pfile, nil} ->
  #       Map.put(msg, :remote_profile_send, {:failed, :not_found})
  #
  #     error ->
  #       Map.put(msg, :remote_profile_send, {:failed, error})
  #   end
  # end

  # defp log_boot_if_needed(
  #        %{
  #          type: "boot",
  #          firmware_vsn: vsn,
  #          reset_reason: reset,
  #          heap_free: heap_free,
  #          heap_min: heap_min,
  #          ap_rssi: ap_rssi,
  #          remote_host: remote_host
  #        } = msg
  #      ) do
  #   log = Map.get(msg, :log, true)
  #
  #   with {:ok, %Schema{name: name}} <- remote_host,
  #        true <- log do
  #     heap_free = (heap_free / 1024) |> Float.round(1) |> Float.to_string()
  #     heap_min = (heap_min / 1024) |> Float.round(1) |> Float.to_string()
  #
  #     heap = ["heap(", heap_min, "k,", heap_free, "k)"] |> IO.iodata_to_binary()
  #     ap_db = [Integer.to_string(ap_rssi), "dB"] |> IO.iodata_to_binary()
  #
  #     [name, "BOOT", reset, vsn, ap_db, heap]
  #     |> Enum.join(" ")
  #     |> Logger.info()
  #   else
  #     _ -> nil
  #   end
  #
  #   msg
  # end

  # defp log_boot_if_needed(%{host: host, reset_reason: _reason} = msg) do
  #   ["BOOT message from host=\"", host, "\" did not match"]
  #   |> Logger.warn()
  #
  #   msg
  # end
  #
  # defp log_boot_if_needed(msg), do: msg
end
