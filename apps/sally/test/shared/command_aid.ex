defmodule Sally.CommandAid do
  @moduledoc """
  Supporting functionality for creating Sally.Command for testing
  """

  def add(%{command_add: opts, dev_alias: %Sally.DevAlias{}} = ctx) when is_list(opts) do
    case Enum.into(opts, %{}) do
      %{count: x} when is_integer(x) -> add_many(ctx.dev_alias, opts)
      _ -> %{command: add_one(ctx.dev_alias, opts)}
    end
  end

  def add(%{command_add: opts, dev_alias: [%Sally.DevAlias{} | _]} = ctx) when is_list(opts) do
    dev_aliases = ctx.dev_alias

    for dev_alias <- dev_aliases, reduce: %{command: []} do
      %{command: _} = acc -> add_one(dev_alias, opts) |> accumulate(acc)
    end
  end

  def add(_), do: :ok

  defp accumulate(%Sally.Command{} = cmd, %{command: acc}), do: %{command: [cmd] ++ acc}

  defp add_one(%Sally.DevAlias{} = dev_alias, opts) when is_list(opts) do
    {track_cmd, opts_rest} = Keyword.pop(opts, :track, true)

    cmd_add_opts = Keyword.put_new(opts_rest, :cmd, "on")

    Sally.Command.add(dev_alias, cmd_add_opts)
    |> tap(fn cmd -> if track_cmd, do: Sally.Command.track(cmd, opts_rest) end)
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

        cmd_opts = Keyword.merge([sent_at: sent_at, cmd: cmd_num], final_opts)

        cmd = Sally.Command.add(dev_alias, cmd_opts)

        Sally.Command.track(cmd, cmd_opts)

        accumulate(cmd, acc)
    end
  end
end
