defmodule Remote.DB.Remote do
  @moduledoc """
  Database implementation for Remote
  """

  use Timex

  alias Remote.Schemas.Remote, as: Schema

  def all do
    import Ecto.Query, only: [from: 2]

    from(
      rem in Schema,
      select: rem
    )
    |> Repo.all()
  end

  def change_name(id, new_name) when is_integer(id) and is_binary(new_name) do
    remote = Repo.get(Schema, id)

    if remote do
      case change_name(remote.host, new_name) do
        :ok -> new_name
        failed -> failed
      end
    else
      :not_found
    end
  end

  def change_name(host, new_name)
      when is_binary(host) and is_binary(new_name) do
    import Remote.Schemas.Remote, only: [changeset: 2]

    remote = find_by_host(host)
    check = find(new_name)

    if is_nil(check) do
      case remote do
        %Schema{} ->
          {res, rem} = changeset(remote, %{name: new_name}) |> Repo.update()

          # Remote names are set upon receipt of their Profile
          # so, if the %Schema{} update succeeded we need to send a restart
          # command
          if res == :ok, do: Remote.restart(rem.name)

          res

        _nomatch ->
          :not_found
      end
    else
      :name_in_use
    end
  end

  def change_name(_, _), do: {:error, :bad_args}

  @doc """
  Delete a Remote by Name or id
  """

  @doc since: "0.0.21"
  def delete(id) when is_integer(id) do
    alias Remote.Schemas.Remote, as: Schema

    with %Schema{} = x <- find(id) do
      Repo.delete(x)
    else
      _catchall -> {:not_found, id}
    end
  end

  def delete_all(:dangerous) do
    import Ecto.Query, only: [from: 2]

    for x <- from(x in Schema, select: [:id]) |> Repo.all() do
      Repo.delete(x)
    end
  end

  def deprecate(:help), do: deprecate()

  def deprecate(what) do
    import Remote.Schemas.Remote, only: [changeset: 2]

    r = find(what)

    if is_nil(r) do
      {:error, :not_found}
    else
      tobe = "~ #{r.name}-#{Timex.now() |> Timex.format!("{ASN1:UTCtime}")}"

      r
      |> changeset(%{name: tobe})
      |> Repo.update()
    end
  end

  def deprecate do
    IO.puts("Usage:")
    IO.puts("\tRemote.deprecate(name|id)")
  end

  def find(id) when is_integer(id),
    do: Repo.get_by(Schema, id: id)

  def find(name) when is_binary(name),
    do: Repo.get_by(Schema, name: name)

  def find(_not_id_or_name), do: nil

  def find_by_host(host) when is_binary(host),
    do: Repo.get_by(Schema, host: host)

  # header to define default parameter for multiple functions
  def mark_as_seen(host, time, threshold_secs \\ 3)

  def mark_as_seen(host, mtime, threshold_secs)
      when is_binary(host) and is_integer(mtime) do
    case find_by_host(host) do
      nil ->
        host

      rem ->
        mark_as_seen(rem, TimeSupport.from_unix(mtime), threshold_secs)
    end
  end

  def mark_as_seen(%Schema{} = rem, %DateTime{} = dt, threshold_secs) do
    import Remote.Schemas.Remote, only: [changeset: 2]

    # only update last seen if more than threshold_secs different
    # this is to avoid high rates of updates when a device hosts many sensors
    if Timex.diff(dt, rem.last_seen_at, :seconds) >= threshold_secs do
      opts = [last_seen_at: dt]
      {res, updated} = changeset(rem, opts) |> Repo.update()
      if res == :ok, do: updated.name, else: rem.name
    else
      rem.name
    end
  end

  def mark_as_seen(nil, _, _), do: nil

  def ota_update_map(%Schema{} = r), do: %{name: r.name, host: r.host}

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

  # create a list of ota updates for all Remotes
  def remote_list(:all) do
    remotes = all()

    for r <- remotes, do: ota_update_map(r)
  end

  # create a list
  def remote_list(id) when is_integer(id) do
    with %Schema{} = r <- find(id),
         map <- ota_update_map(r) do
      [map]
    else
      nil ->
        [:not_found]
    end
  end

  def remote_list(name) when is_binary(name) do
    import Ecto.Query, only: [from: 2]

    q = from(remote in Schema, where: [name: ^name], or_where: [host: ^name])
    rem = Repo.one(q)

    case rem do
      %Schema{} = r ->
        map = ota_update_map(r)
        [map]

      nil ->
        [:not_found]
    end
  end

  def remote_list(list) when is_list(list) do
    make_list = fn list ->
      for l <- list, do: remote_list(l)
    end

    make_list.(list) |> List.flatten()
  end

  def remote_list(catchall) do
    [:unsupported, catchall]
  end

  def set_profile(name_or_id, profile) do
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
