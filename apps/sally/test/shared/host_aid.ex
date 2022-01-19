defmodule Sally.HostAid do
  @moduledoc """
  Supporting functionality for creating Sally.Host for testing
  """

  # NOTE:
  # all functions are intended for use in ExUnit.Case setup functions
  #
  # returns either a map to merge into the context or :ok

  def add(%{host_add: opts}) do
    ident = opts[:ident] || unique(:ident)
    start_at = opts[:start_at] || DateTime.utc_now()
    seen_at = opts[:seen_at] || DateTime.utc_now()

    changes = %{ident: ident, last_start_at: start_at, last_seen_at: seen_at, name: ident}
    replace_cols = [:ident, :last_start_at, :last_seen_at, :name]

    changeset = Sally.Host.changeset(changes)

    case Sally.Repo.insert(changeset, Sally.Host.insert_opts(replace_cols)) do
      {:ok, %Sally.Host{} = host} -> %{host: host}
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

  def setup(%{host_setup: opts, host: %Sally.Host{} = host}) do
    name = opts[:name] || unique(:name)
    profile = opts[:profile] || "generic"

    case Sally.Host.setup(host, name: name, profile: profile) do
      {:ok, %Sally.Host{} = host} -> %{host: host}
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
