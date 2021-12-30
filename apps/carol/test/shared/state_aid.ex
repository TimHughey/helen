defmodule Carol.StateAid do
  @doc """
  Add %State{} to testing context

  State fields set by default: `:alfred, :server_name, :equipment, :programs`

  ```

  ```

  """
  @doc since: "0.2.1"
  def add(%{state_add: opts} = ctx) when is_list(opts) do
    alfred = ctx[:alfred] || AlfredSim
    server_name = ctx[:server_name] || __MODULE__
    equipment = ctx[:equipment] || "equipment missing"

    new_state =
      [
        opts: [alfred: alfred, timezone: "America/New_York"],
        id: server_name,
        equipment: equipment,
        episodes: ctx[:episodes] || :none
      ]
      |> Carol.State.new()

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
