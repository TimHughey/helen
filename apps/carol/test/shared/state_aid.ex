defmodule Carol.StateAid do
  @moduledoc false

  def add(%{state_add: opts} = ctx) when is_list(opts) do
    alfred = ctx[:alfred] || AlfredSim
    server_name = ctx[:server_name] || __MODULE__
    equipment = ctx[:equipment] || "equipment missing"

    fields = [
      opts: [alfred: alfred, timezone: "America/New_York"],
      id: server_name,
      equipment: equipment,
      episodes: ctx[:episodes] || :none
    ]

    new_state = Carol.State.new(fields)

    case Enum.into(opts, %{}) do
      %{bootstrap: true} -> Carol.Server.handle_continue(:bootstrap, new_state)
      _ -> new_state
    end
    |> rationalize(opts)
    |> then(fn state -> %{state: state} end)
  end

  def add(_), do: :ok

  def rationalize(result, opts) do
    cond do
      opts[:raw] == true and is_tuple(result) -> result
      is_tuple(result) and tuple_size(result) > 0 -> elem(result, 1)
      true -> result
    end
  end
end
