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
