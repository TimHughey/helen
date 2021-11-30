defmodule Sally.HostAid do
  alias Sally.{Host, Repo}

  # NOTE:
  # all functions are intended for use in ExUnit.Case setup functions
  #
  # returns either a map to merge into the context or :ok

  def add(%{host_add: opts}) do
    alias Sally.Host.ChangeControl

    ident = opts[:ident] || unique(:ident)
    start_at = opts[:start_at] || DateTime.utc_now()
    seen_at = opts[:seen_at] || DateTime.utc_now()

    want_keys = [:ident, :last_start_at, :last_seen_at, :name]

    cc = %ChangeControl{
      raw_changes: %{ident: ident, last_start_at: start_at, last_seen_at: seen_at, name: ident},
      required: want_keys,
      replace: want_keys
    }

    changes = Host.changeset(cc)

    case Repo.insert(changes, Host.insert_opts(cc.replace)) do
      {:ok, %Host{} = host} -> %{host: host}
      _ -> :fail
    end
  end

  def add(_ctx), do: :ok

  def make_payload(:boot, opts) do
    start_at = opts[:start_at] || DateTime.utc_now()
    mtime = DateTime.to_unix(start_at, :millisecond) - 3

    %{
      mtime: mtime,
      elapsed_ms: 5981,
      tasks: 12,
      stack: %{size: 4096, highwater: 1024}
    }
    # NOTE: must use iodata: false since we're simulating in bound data
    |> Msgpax.pack!(iodata: false)
  end

  def make_payload(:startup, opts) do
    start_at = opts[:start_at] || DateTime.utc_now()
    mtime = DateTime.to_unix(start_at, :millisecond) - 3

    %{
      mtime: mtime,
      firmware_vsn: "00.00.00",
      idf_vsn: "v4.3.1",
      app_sha: "01abcdef",
      build_date: "Jul 1 2021",
      build_time: "13:23",
      reset_reason: "power on"
    }
    # NOTE: must use iodata: false since we're simulating in bound data
    |> Msgpax.pack!(iodata: false)
  end

  def setup(%{host_setup: opts, host: %Host{} = host}) do
    name = opts[:name] || unique(:name)
    profile = opts[:profile] || "generic"

    case Host.setup(host, name: name, profile: profile) do
      {:ok, %Host{} = host} -> %{host: host}
      _ -> :fail
    end
  end

  def setup(_ctx), do: :ok

  def unique(what) when is_atom(what) do
    unique = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case what do
      :ident -> "host.#{unique}"
      :name -> "hostname_#{unique}"
    end
  end
end
