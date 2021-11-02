defmodule Sally.Test.Support do
  def add_device(%Sally.Host{} = host, opts) do
    device = Ecto.build_assoc(host, :devices)

    cond do
      opts[:auto] == :mcp23008 ->
        %{ident: unique(:mcp23008), pios: 8, family: "i2c", mutable: true}

      opts[:auto] == :ds ->
        %{ident: unique(:ds), pios: 1, family: "ds", mutable: false}

      true ->
        %{
          ident: opts[:device] || opts[:ident],
          pios: opts[:pios] || 10,
          family: opts[:family],
          mutable: opts[:mutable]
        }
    end
    |> Map.merge(%{last_seen_at: opts[:last_seen_at] || DateTime.utc_now()})
    |> Sally.Device.changeset(device)
    |> Sally.Repo.insert!(
      on_conflict: {:replace, Sally.Device.columns(:replace)},
      returning: true,
      conflict_target: [:ident]
    )
  end

  def add_host(opts) do
    alias Sally.Host.ChangeControl

    raw = %{
      ident: opts[:host] || opts[:ident] || unique(:host),
      name: opts[:name] || unique(:name),
      profile: opts[:profile] || "generic",
      last_start_at: opts[:last_start_at] || DateTime.utc_now(),
      last_seen_at: opts[:last_seen_at] || DateTime.utc_now()
    }

    cc = %ChangeControl{
      raw_changes: raw,
      required: Map.keys(raw),
      replace: raw |> Map.drop([:ident, :name, :inserted_at]) |> Map.keys()
    }

    Sally.Host.changeset(cc) |> Sally.Repo.insert!(Sally.Host.insert_opts(cc.replace))

    # %{
    #   host: opts[:host] || opts[:ident],
    #   name: opts[:name],
    #   profile: opts[:profile] || "generic",
    #   last_start_at: opts[:last_start_at] || DateTime.utc_now(),
    #   last_seen_at: opts[:last_seen_at] || DateTime.utc_now()
    # }
    # |> Sally.Host.changeset()
    # |> Sally.Repo.insert!(
    #   on_conflict: {:replace, Sally.Host.columns(:replace)},
    #   returning: true,
    #   conflict_target: [:ident]
    # )
  end

  def add_command(%Sally.DevAlias{} = dev_alias, cmd) do
    Sally.Command.add(dev_alias, cmd, [])
  end

  def delete_dev_aliases do
    for dev_alias <- Sally.Repo.all(Sally.DevAlias) do
      case Sally.DevAlias.delete(dev_alias.id) do
        {:ok, results} -> [name: results[:name], commands: results[:commands]]
        e -> [name: dev_alias.name, error: e]
      end
    end
  end

  def unique(what) when is_atom(what) do
    unique = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case what do
      :host -> "host.#{unique}"
      :dev_alias -> "dev alias #{unique}"
      :ds -> "ds.#{unique}"
      :mcp23008 -> "i2c.#{unique}.mcp23008.20"
      :name -> "name #{unique}"
    end
  end

  # def unique_string do
  #   Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)
  # end
end
