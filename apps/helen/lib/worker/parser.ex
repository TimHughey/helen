defmodule Helen.Worker.Config.Parser do
  @moduledoc false

  require Logger

  def parse(str) do
    with {:ok, tokens, _} <- :mc_lexer.string(to_char_list(str)),
         {:ok, parsed} <- :mc_parser.parse(tokens) do
      {:ok,
       collapse(parsed, :modes)
       |> collapse(:commands)
       |> Enum.into(%{})}
    else
      {:error, {line, :mc_lexer, reason}, _} ->
        {:error, {reason, line}}

      {:error, {line, :mc_parser, reason}} ->
        Logger.warn("#{Enum.join(reason)} (line #{line})")

        {:error, {reason, line}}
    end
  end

  def collapse(parsed, collection) do
    import String, only: [to_atom: 1, trim_trailing: 2]

    key = to_string(collection) |> trim_trailing("s") |> to_atom()

    {items, rest} = Keyword.split(parsed, [key])

    for {^key, details} when is_map(details) <- items,
        reduce: Keyword.put_new(rest, collection, %{}) do
      parsed ->
        case details do
          %{cmd: cmd} ->
            put_in(parsed, [collection, cmd], details)

          %{name: name} ->
            put_in(parsed, [collection, name], details)
        end
    end
  end
end
