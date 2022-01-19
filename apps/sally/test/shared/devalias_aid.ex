defmodule Sally.DevAliasAid do
  @moduledoc """
  Supporting functionality for creating Sally.DevAlias for testing
  """

  def add(%{devalias_add: opts, device: %Sally.Device{} = device}) when is_list(opts) do
    count = opts[:count] || 1

    if count == 1 do
      add_one(device, opts)
    else
      # must create unique names when adding many
      opts = Keyword.drop(opts, [:name])

      # accumulate created devalias as created
      # if error return it causing setup to fali
      for _counter <- 1..count, reduce: %{dev_alias: []} do
        %{dev_alias: acc} when is_list(acc) ->
          case add_one(device, opts) do
            %{dev_alias: new_devalias} -> %{dev_alias: [new_devalias] ++ acc}
            error -> error
          end

        error ->
          error
      end
    end
  end

  def add(_), do: :ok

  def just_saw(%{just_saw: opts, device: %Sally.Device{}} = ctx) when is_list(opts) do
    dev_aliases = Sally.Device.load_aliases(ctx.device).aliases

    %{sally_just_saw_v3: Sally.DevAlias.just_saw(dev_aliases)}
  end

  def just_saw(_), do: :ok

  def random_pick([%Sally.DevAlias{} | _] = dev_aliases, count \\ 1) do
    picked = Enum.take_random(dev_aliases, count)

    if count == 1, do: List.first(picked), else: picked
  end

  def unique(x) when x in [:devalias, :dev_alias] do
    x = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    ["devalias_", x] |> IO.iodata_to_binary()
  end

  defp add_one(%Sally.Device{} = device, opts) when is_list(opts) do
    aliases = Sally.DeviceAid.aliases(device)
    name = opts[:name] || unique(:devalias)
    pio = if(device.mutable, do: Sally.DeviceAid.next_pio(aliases), else: 0)
    nature = if(device.mutable, do: :cmds, else: :datapoints)
    ttl_ms = opts[:ttl_ms] || 15_000

    params = [name: name, pio: pio, description: description(), ttl_ms: ttl_ms]

    Sally.DevAlias.create(device, params) |> register(nature, opts)
  end

  defp description do
    Ecto.UUID.generate() |> String.replace("-", " ")
  end

  defp register({:ok, %Sally.DevAlias{} = dev_alias}, nature, opts) do
    register_opts = Keyword.get(opts, :register, [])

    if register_opts do
      allowed_opts = Alfred.Name.allowed_opts()
      register_opts = Keyword.take(opts, allowed_opts) |> Keyword.put_new(:nature, nature)

      rc = Sally.DevAlias.just_saw(dev_alias, register_opts)

      %{dev_alias: dev_alias, name_registration: %{rc: rc, name: dev_alias.name, nature: nature}}
    else
      %{dev_alias: dev_alias, name_registration: :none}
    end
  end

  defp register(error, _nature, _opts), do: %{dev_alias: error}

  # defp next_pio(dev_aliases) do
  #   all_pios = [0..7] |> Enum.to_list()
  #   used_pios = for %Sally.DevAlias{pio: x} <- dev_aliases, do: x
  #
  #   available_pios = all_pios -- used_pios
  #
  #   case available_pios do
  #     [] -> 0
  #     [x | _] -> x
  #   end
  # end
end
