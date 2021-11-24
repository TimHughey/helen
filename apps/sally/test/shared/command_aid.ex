defmodule Sally.CommandAid do
  alias Sally.{Command, DevAlias, Execute}

  def add(%{command_add: opts, dev_alias: %DevAlias{}} = ctx) when is_list(opts) do
    case Enum.into(opts, %{}) do
      %{count: x} when is_integer(x) -> add_many(ctx.dev_alias, opts)
      _ -> %{command: add_one(ctx.dev_alias, opts)}
    end
  end

  def add(%{command_add: opts, dev_alias: [%DevAlias{} | _]} = ctx) when is_list(opts) do
    dev_aliases = ctx.dev_alias

    for dev_alias <- dev_aliases, reduce: %{command: []} do
      %{command: _} = acc -> add_one(dev_alias, opts) |> accumulate(acc)
    end
  end

  def add(_), do: :ok

  defp accumulate(%Command{} = cmd, %{command: acc}), do: %{command: [cmd] ++ acc}

  defp add_one(%DevAlias{} = dev_alias, opts) when is_list(opts) do
    {cmd, opts_rest} = Keyword.pop(opts, :cmd, "on")
    {track_cmd, opts_rest} = Keyword.pop(opts_rest, :track, false)

    Command.add(dev_alias, cmd, opts_rest)
    |> tap(fn cmd -> if(track_cmd, do: Execute.track(cmd, opts_rest)) end)
  end

  defp add_many(dev_alias, opts) do
    {count, opts_rest} = Keyword.pop(opts, :count)
    {shift_unit, opts_rest} = Keyword.pop(opts_rest, :shift_unit, :minutes)
    {shift_increment, opts_rest} = Keyword.pop(opts_rest, :shift_increment, -1)
    {cmd, opts_rest} = Keyword.pop(opts_rest, :cmd, "on")

    final_opts = Keyword.put_new(opts_rest, :ack, :immediate)

    dt_base = Timex.now()

    for num <- count..1, reduce: %{command: []} do
      %{command: _} = acc ->
        cmd_num = [cmd, Integer.to_string(num) |> String.pad_leading(4, "0")] |> Enum.join(" ")
        shift_opts = [{shift_unit, num * shift_increment}]
        sent_at = Timex.shift(dt_base, shift_opts)

        cmd_opts = [sent_at: sent_at] ++ final_opts

        Command.add(dev_alias, cmd_num, cmd_opts) |> accumulate(acc)
    end
  end
end
