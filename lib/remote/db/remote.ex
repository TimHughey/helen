defmodule Remote.DB.Remote do
  @moduledoc """
  Database implementation for Remote
  """

  use Timex

  alias Remote.Schemas.Remote, as: Schema

  def add(%Schema{} = r), do: add([r])

  def add(%{host: host, mtime: mtime} = r) do
    [
      %Schema{
        host: host,
        name: Map.get(r, :name, host),
        firmware_vsn: Map.get(r, :vsn, "not available"),
        idf_vsn: Map.get(r, :idf, "not available"),
        app_elf_sha256: Map.get(r, :sha, "not available"),
        build_date: Map.get(r, :bdate, "not available"),
        build_time: Map.get(r, :btime, "not available"),
        last_seen_at: TimeSupport.from_unix(mtime),
        last_start_at: TimeSupport.from_unix(mtime)
      }
    ]
    |> add()
  end

  def add(list) when is_list(list) do
    for %Schema{} = r <- list do
      case find_by_host(r.host) do
        nil ->
          Repo.insert!(r)

        found ->
          found
      end
    end
  end

  def add(_no_match) do
    {:failed, :not_remote}
  end

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

  def update_from_external(%Schema{} = rem, eu) do
    import Remote.Schemas.Remote, only: [changeset: 2]

    params = %{
      # remote_runtime messages:
      #  :last_start_at is added to map for boot messages when not available
      #   keep existing time
      last_seen_at: Map.get(eu, :last_seen_at, rem.last_seen_at),
      firmware_vsn: Map.get(eu, :vsn, rem.firmware_vsn),
      idf_vsn: Map.get(eu, :idf, rem.idf_vsn),
      app_elf_sha256: Map.get(eu, :sha, rem.app_elf_sha256),
      build_date: Map.get(eu, :bdate, rem.build_date),
      build_time: Map.get(eu, :btime, rem.build_time),
      # reset the following metrics when not present
      ap_rssi: Map.get(eu, :ap_rssi, 0),
      ap_pri_chan: Map.get(eu, :ap_pri_chan, 0),
      bssid: Map.get(eu, :bssid, "xx:xx:xx:xx:xx:xx"),
      batt_mv: Map.get(eu, :batt_mv, 0),
      heap_free: Map.get(eu, :heap_free, 0),
      heap_min: Map.get(eu, :heap_min, 0),
      uptime_us: Map.get(eu, :uptime_us, 0),

      # boot messages:
      #  :last_start_at is added to map for boot messages not present
      #   keep existing time
      last_start_at: Map.get(eu, :last_start_at, rem.last_start_at),
      reset_reason: Map.get(eu, :reset_reason, rem.reset_reason)
    }

    changeset(rem, params) |> Repo.update()
  end

  def update_from_external({:error, _}, _), do: {:error, "bad update"}
end
