defmodule Broom.Test.Support do
  @moduledoc false

  def add_dev_alias(%Broom.Device{} = device, opts) do
    Broom.DevAlias.create(device, opts)
  end

  def add_device(%Broom.Host{} = host, opts) do
    device = Ecto.build_assoc(host, :devices)

    %{
      ident: opts[:device] || opts[:ident],
      pios: opts[:pios] || 10,
      family: opts[:family],
      mutable: opts[:mutable],
      last_seen_at: opts[:last_seen_at] || DateTime.utc_now()
    }
    |> Broom.Device.changeset(device)
    |> Broom.Repo.insert!(
      on_conflict: {:replace, Broom.Device.columns(:replace)},
      returning: true,
      conflict_target: [:ident]
    )
  end

  def add_host(opts) do
    %{
      host: opts[:host] || opts[:ident],
      name: opts[:name],
      profile: opts[:profile] || "generic",
      last_start_at: opts[:last_start_at] || DateTime.utc_now(),
      last_seen_at: opts[:last_seen_at] || DateTime.utc_now()
    }
    |> Broom.Host.changeset()
    |> Broom.Repo.insert!(
      on_conflict: {:replace, Broom.Host.columns(:replace)},
      returning: true,
      conflict_target: [:ident]
    )
  end

  def add_command(%Broom.DevAlias{} = dev_alias, cmd) do
    Broom.Command.add(dev_alias, cmd, [])
  end
end
