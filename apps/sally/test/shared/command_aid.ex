defmodule Sally.CommandAid do
  alias Sally.{Command, DevAlias, Execute}

  def add(%{command_add: opts, dev_alias: %DevAlias{}} = ctx) when is_list(opts) do
    %{command: add_one(ctx.dev_alias, opts)}
  end

  def add(%{command_add: opts, dev_alias: [%DevAlias{} | _]} = ctx) when is_list(opts) do
    dev_aliases = ctx.dev_alias

    # accumulate created commands
    # if error return it causing setup to fali
    for dev_alias <- dev_aliases, reduce: %{command: []} do
      %{command: acc} when is_list(acc) ->
        case add_one(dev_alias, opts) do
          %Command{} = x -> %{command: [x] ++ acc}
          error -> error
        end

      error ->
        error
    end
  end

  def add(_), do: :ok

  defp add_one(%DevAlias{} = dev_alias, opts) when is_list(opts) do
    {cmd, opts_rest} = Keyword.pop(opts, :cmd, "on")
    {track_cmd, opts_rest} = Keyword.pop(opts_rest, :track, false)

    Command.add(dev_alias, cmd, opts_rest)
    |> tap(fn cmd -> if(track_cmd, do: Execute.track(cmd, opts_rest)) end)
  end
end
