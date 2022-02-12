defmodule Carol.InitAid do
  @moduledoc false

  @tz "America/New_York"

  def add(%{} = ctx) do
    case ctx do
      %{init_add: opts} ->
        init_args = add(opts)
        {dev_alias, init_args} = Keyword.pop(init_args, :dev_alias)

        %{init_args: init_args, dev_alias: dev_alias}

      _ ->
        :ok
    end
  end

  @add_steps [:equipment, :episodes, :instance, :opts]
  def add([_ | _] = opts) do
    ref_dt = Timex.now(@tz)
    opts_map = Enum.into(opts, %{ref_dt: ref_dt, timezone: @tz, defaults: []})

    Enum.reduce(@add_steps, opts_map, fn
      :equipment, opts_map -> equipment(opts_map)
      :episodes, opts_map -> episodes(opts_map)
      :instance, opts_map -> instance(opts_map)
      :opts, %{timezone: tz} = x -> put_in(x, [:opts], echo: :tick, caller: self(), timezone: tz)
    end)
    |> Map.take([:dev_alias, :episodes, :equipment, :instance, :opts, :defaults])
    |> Enum.into([])
  end

  def instance(opts_map) do
    instance = Alfred.NamesAid.unique("carol")

    put_in(opts_map, [:instance], instance)
  end

  def episodes(opts_map) do
    unless match?(%{episodes: {_, [_ | _]}}, opts_map), do: raise("must provide episodes opts")

    {what, epi_opts} = get_in(opts_map, [:episodes])

    opts = Map.take(opts_map, [:equipment, :ref_dt, :timezone]) |> Enum.into([])
    episodes = Carol.EpisodeAid.add(what, epi_opts, opts)

    put_in(opts_map, [:episodes], episodes)
  end

  def equipment(opts_map) do
    opts = Map.get(opts_map, :equip, [])

    dev_alias = Alfred.NamesAid.new_dev_alias(:equipment, opts)

    Map.merge(opts_map, %{equipment: dev_alias.name, dev_alias: dev_alias})
  end
end
