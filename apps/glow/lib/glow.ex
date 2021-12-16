defmodule Glow do
  @moduledoc """
  Documentation for `Glow`.
  """

  alias Carol.{Program, State}
  alias Glow.Instance

  @doc """
  Get the cmd for an instance
  """
  @doc since: "0.1.6"
  def cmd(child_pattern, program_id) do
    case child_search(child_pattern) do
      [] -> {:unknown_child, child_pattern}
      [child] -> Carol.program(child, id: program_id, params: true)
      multiple -> {:multiple_children, multiple}
    end
  end

  @doc """
  Adjust the command for a instance program
  """
  @doc since: "0.1.6"
  def cmd_adjust_params(child_pattern, program_id, params) do
    opts = [id: program_id, cmd_params: params]
    msg = {:adjust, :cmd_params, opts}

    case child_search(child_pattern) do
      [] -> {:unknown_child, child_pattern}
      [child] -> Carol.Server.call(child, msg)
      multiple -> {:multiple_children, multiple}
    end
  end

  @doc since: "0.1.0"
  def state do
    instances = children()

    puts_child_list("Get State")

    selected = IO.gets("\nInstance? ") |> String.trim() |> String.to_integer()
    instance = Enum.at(instances, selected - 1)

    :sys.get_state(instance)
  end

  def children do
    for {id, _, _, _} <- Supervisor.which_children(Glow.Supervisor), do: id
  end

  def child_search(like) when is_binary(like) do
    # like = String.downcase(like)
    # names = Enum.map(children(), fn x -> Instance.display-name(x) |> String.downcase())
    # names = for(child <- children(), do: Instance.display_name(child) |> String.downcase())
    #
    # Enum.filter(names, fn name -> String.contains?(name, like) end)

    like = String.downcase(like)

    for child <- children(), reduce: [] do
      acc ->
        name = Instance.display_name(child) |> String.downcase()

        if String.contains?(name, like), do: [child | acc], else: acc
    end
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
