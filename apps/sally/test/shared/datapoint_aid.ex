defmodule Sally.DatapointAid do
  alias Sally.{Datapoint, DevAlias, Repo}

  def add(%{datapoint_add: opts, dev_alias: %DevAlias{}} = ctx) when is_list(opts) do
    case Enum.into(opts, %{}) do
      %{count: x} when is_integer(x) -> add_many(ctx.dev_alias, opts)
      _ -> %{datapoint: add_one(ctx.dev_alias, opts)}
    end
  end

  def add(%{datapoint_add: opts, dev_alias: [%DevAlias{} | _]} = ctx) when is_list(opts) do
    dev_aliases = ctx.dev_alias

    for dev_alias <- dev_aliases, reduce: %{datapoint: []} do
      %{datapoint: _} = acc -> add_one(dev_alias, opts) |> accumulate(acc)
    end
  end

  def add(_), do: :ok

  defp accumulate(%Datapoint{} = cmd, %{datapoint: acc}), do: %{datapoint: [cmd] ++ acc}

  defp add_one(%DevAlias{} = dev_alias, opts) when is_list(opts) do
    {data, opts_rest} = Keyword.pop(opts, :data, %{temp_c: 21.1, relhum: 54.2})
    {reading_at, _opts_rest} = Keyword.pop(opts_rest, :reading_at, Timex.now())

    Ecto.Multi.new()
    |> Ecto.Multi.put(:aliases, [dev_alias])
    |> Ecto.Multi.run(:datapoint, DevAlias, :add_datapoint, [data, reading_at])
    |> Repo.transaction()
    |> detuple_txn_result()
  end

  defp add_many(dev_alias, opts) do
    {count, opts_rest} = Keyword.pop(opts, :count)
    {shift_unit, opts_rest} = Keyword.pop(opts_rest, :shift_unit, :minutes)
    {shift_increment, _opts_rest} = Keyword.pop(opts_rest, :shift_increment, -1)

    dt_base = Timex.now()

    for num <- count..1, reduce: %{datapoint: []} do
      %{datapoint: _} = acc ->
        shift_opts = [{shift_unit, num * shift_increment}]
        reading_at = Timex.shift(dt_base, shift_opts)

        revised_opts = Keyword.put(opts, :reading_at, reading_at)

        add_one(dev_alias, revised_opts) |> accumulate(acc)
    end
  end

  defp detuple_txn_result({:ok, map}), do: map.datapoint |> List.first()
  defp detuple_txn_result({:error, _}), do: nil
end
