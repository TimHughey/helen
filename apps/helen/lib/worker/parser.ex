defmodule Helen.Worker.Config.Parser do
  @moduledoc false

  require Logger

  def finalize({:ok, parsed}) do
    {:ok,
     for {mode_name, details} <- required_modes(), reduce: parsed do
       parsed -> put_in(parsed, [:modes, mode_name], details)
     end}
  end

  def finalize(passthrough), do: passthrough

  def parse(str) do
    with {:ok, tokens, _} <- :mc_lexer.string(to_charlist(str)),
         {:ok, parsed} <- :mc_parser.parse(tokens) do
      {:ok,
       collapse(parsed, :modes)
       |> collapse(:mode_steps)
       |> collapse(:commands)
       |> finalize()
       |> Enum.into(%{})}
    else
      {:error, {line, :mc_lexer, reason}, _} ->
        {:error, {reason, line}}

      {:error, {line, :mc_parser, reason}} ->
        Logger.warn("#{Enum.join(reason)} (line #{line})")

        {:error, {reason, line}}
    end
  end

  def collapse(parsed, collection) when collection in [:modes, :commands] do
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

  def collapse(parsed, :mode_steps) do
    modes = get_in(parsed, [:modes])

    for {mode_name, %{details: mode_details}} <- modes, reduce: parsed do
      parsed ->
        # mode details is a keyword list with key :details and one or more
        # :step keys
        {steps, mode_meta} = Keyword.split(mode_details, [:step])

        # populate the mode with only the meta data, the following for will
        # handle the steps
        parsed =
          put_in(parsed, [:modes, mode_name, :details], mode_meta)
          |> put_in([:modes, mode_name, :details, :steps], %{})

        # reduce parsed with the transformation of the list of steps into a map
        for {:step, %{name: step_name} = step_details} <- steps,
            reduce: parsed do
          parsed ->
            put_in(
              parsed,
              [:modes, mode_name, :details, :steps, step_name],
              step_details
            )
        end
    end
  end

  def required_modes do
    [
      all_stop: %{
        details: [
          next_mode: :hold,
          sequence: [:all_stop],
          steps: %{
            all_stop: %{
              actions: [%{cmd: :off, worker_name: :all}]
            }
          }
        ],
        name: :all_stop
      }
    ]
  end
end
