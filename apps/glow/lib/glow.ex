defmodule Glow do
  @moduledoc """
  Documentation for `Glow`.
  """

  alias Glow.Instance

  @doc since: "0.1.0"
  def state do
    instances = children()

    puts_child_list("Get State")

    selected = IO.gets("\nInstance? ") |> String.trim() |> String.to_integer()
    instance = Enum.at(instances, selected - 1)

    :sys.get_state(instance) |> inspect(pretty: true) |> IO.puts()
  end

  def children do
    for {id, _, _, _} <- Supervisor.which_children(Glow.Supervisor), do: id
  end

  @doc false
  def puts_child_list(heading) do
    [heading, "\n"] |> IO.puts()

    display_names = for x <- children(), do: Instance.display_name(x)

    for name <- display_names, reduce: 1 do
      acc ->
        ["   ", Integer.to_string(acc), ". ", name] |> IO.puts()

        acc + 1
    end
  end
end
