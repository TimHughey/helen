defmodule Carol.StateAid do
  @moduledoc false

  def add(%{state_add: opts} = ctx) when is_list(opts) do
    alfred = ctx[:alfred] || AlfredSim

    fields = [
      opts: [alfred: alfred, timezone: "America/New_York"],
      id: ctx[:server_name] || __MODULE__,
      instance: ctx[:instance_name] || Alfred.NamesAid.unique("carol"),
      equipment: ctx[:equipment] || "equipment missing",
      episodes: ctx[:episodes] || :none
    ]

    new_state = Carol.State.new(fields)

    case Enum.into(opts, %{}) do
      %{tick: true} -> handle_continues(new_state, [:bootstrap, :tick])
      %{bootstrap: true} -> handle_continues(new_state, [:bootstrap])
      _ -> new_state
    end
    |> rationalize(opts)
    |> then(fn state -> %{state: state} end)
  end

  def add(_), do: :ok

  def handle_continues(state, steps) do
    Enum.reduce(steps, state, &invoke_handle_continue(&1, &2))
  end

  def invoke_handle_continue(step, state_or_tuple) do
    case state_or_tuple do
      %{} = state -> state
      {_, state} -> state
      {_, state, _} -> state
    end
    |> then(fn state -> Carol.Server.handle_continue(step, state) end)
  end

  def rationalize(result, opts) do
    cond do
      opts[:raw] == true and is_tuple(result) -> result
      is_tuple(result) and tuple_size(result) > 0 -> elem(result, 1)
      true -> result
    end
  end
end
