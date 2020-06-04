defmodule Remote.DB.Remote do
  @moduledoc """
  Database implementation for Remote
  """

  use Timex

  alias Remote.Schemas.Remote, as: Schema

  @doc """
  Delete a Remote by Name, ID or (as last resort) Host
  """

  @doc since: "0.0.21"
  def delete(name_id_host) do
    alias Remote.Schemas.Remote, as: Schema

    with %Schema{} = x <- find(name_id_host) do
      Repo.delete(x)
    else
      nil -> {:not_found, name_id_host}
      error -> error
    end
  end

  def delete_all(:dangerous) do
    import Ecto.Query, only: [from: 2]

    for x <- from(x in Schema, select: [:id]) |> Repo.all() do
      Repo.delete(x)
    end
  end

  def deprecate(name_id_host) do
    import Remote.Schemas.Remote, only: [changeset: 2]

    with %Schema{name: name} <- find(name_id_host),
         time_str <- Timex.now() |> Timex.format!("{ASN1:UTCtime}"),
         tobe_name <- ["~ ", name, ":", time_str] |> IO.iodata_to_binary() do
      rename(name_id_host, tobe_name)
    else
      _not_found -> {:not_found, name_id_host}
    end
  end

  @doc """
    Get a Remmote by id, name or (as a last resort) by host

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Remote.Schemas.Remote{}

      ## Examples
        iex> Remote.DB.Remote.find("test-builder")
        %Remote.Schemas.Remote{}
  """

  @doc since: "0.0.21"
  def find(id_or_name) do
    check_args = fn
      x when is_binary(x) -> [name: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2]

    with opts when is_list(opts) <- check_args.(id_or_name),
         %Schema{} = found <- get_by(Schema, opts) do
      found
    else
      {:bad_args, _} = x -> x
      x when is_nil(x) -> get_by(Schema, host: id_or_name)
      x -> {:error, x}
    end
  end

  @doc since: "0.0.21"
  def names, do: names_begin_with("")

  @doc """
    Retrieve a list of Remote names that begin with a pattern
  """

  @doc since: "0.0.9"
  def names_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(r in Schema,
      where: like(r.name, ^like_string),
      order_by: r.name,
      select: r.name
    )
    |> Repo.all()
  end

  def profile_assign(name_or_id, profile) do
    import Remote.Schemas.Remote, only: [changeset: 2]
    alias Remote.Schemas.Profile
    alias Remote.DB.Profile, as: DBP

    with %Schema{} = x <- find(name_or_id),
         {:profile, %Profile{name: name}} <- {:profile, DBP.find(profile)},
         cs <- changeset(x, %{profile: name}),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?},
         {:ok, %Schema{name: name, profile: profile}} <- Repo.update(cs) do
      [remote: [name: name, profile: profile]]
    else
      nil -> {:not_found, name_or_id}
      {:profile, nil} -> {:not_found, profile}
      {:cs_valid, cs, false} -> {:invalid_changes, cs}
      error -> {:error, error}
    end
  end

  @doc """
    Rename a Remote

    NOTE: the remote to rename is found by id, name or host
  """

  @doc since: "0.0.21"
  def rename(existing_name_id_host, new_name) when is_binary(new_name) do
    import Remote.Schemas.Remote, only: [changeset: 2]

    to_find = existing_name_id_host

    with {:find, %Schema{name: was} = x} <- {:find, find(to_find)},
         cs <- changeset(x, %{name: new_name}),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?},
         {:ok, %Schema{name: name}} <- Repo.update(cs) do
      [remote: [was_named: was, now_named: name]]
    else
      {:find, nil} -> {:not_found, to_find}
      {:cs_valid, cs, false} -> {:invalid_changes, cs}
      error -> {:error, error}
    end
  end

  @doc """
  Upsert (insert or update) a Sensor.Schemas.Device

  input:
    a. message from an external source or or a map with necessary keys:
       %{device: string, host: string, dev_latency_us: integer, mtime: integer}

  returns input message populated with:
   a. sensor_device: the results of upsert/2
     * {:ok, %Sensor.Schemas.Device{}}
     * {:invalid_changes, %Changeset{}}
     * {:error, actual error results from upsert/2}
  """

  @doc since: "0.0.15"
  def upsert(%{host: _, name: _, mtime: _mtime} = msg) do
    import TimeSupport, only: [from_unix: 1, utc_now: 0]

    params = [
      :host,
      :name,
      :firmware_vsn,
      :idf_vsn,
      :app_elf_sha256,
      :build_date,
      :build_time,
      :ap_rssi,
      :ap_pri_chan,
      :bssid,
      :batt_mv,
      :heap_free,
      :heap_min,
      :uptime_us,
      :last_seen_at,
      :last_start_at,
      :reset_reason
    ]

    # create a map of defaults for keys that may not exist in the msg
    params_default = %{last_seen_at: utc_now()} |> add_last_start_if_needed(msg)

    # assemble a map of changes
    # NOTE:  the second map passed to Map.merge/2 replaces duplicate keys
    #        in the first map.  in this case we want all available data from
    #        the message however if some isn't available we provide it via
    #        changes_default
    params = Map.merge(params_default, Map.take(msg, params))

    # assemble the return message with the results of upsert/2
    Map.put(msg, :remote_host, upsert(%Schema{}, params))
  end

  def upsert(msg) when is_map(msg),
    do: Map.put(msg, :remote_host, {:error, :badmsg})

  def upsert(%Schema{} = x, params) when is_map(params) or is_list(params) do
    import Remote.Schemas.Remote, only: [changeset: 2, keys_replace: 1]

    # assemble the opts for upsert
    # check for conflicts on :host
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys_replace(params)},
      returning: true,
      conflict_target: :host
    ]

    # make certain the params are a map
    cs = changeset(x, Enum.into(params, %{}))

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %Schema{id: _id} = rem} <- Repo.insert(cs, opts) do
      {:ok, rem}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  def upsert(_x, params) do
    {:error, params}
  end

  defp add_last_start_if_needed(params, %{type: type} = _msg) do
    import TimeSupport, only: [utc_now: 0]

    case type do
      "boot" -> Map.put(params, :last_start_at, utc_now())
      _ -> params
    end
  end
end
