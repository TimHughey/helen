defmodule Carol.StateAid do
  alias Alfred.ExecCmd
  alias Carol.{Server, State}

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
        alfred: alfred,
        server_name: server_name,
        equipment: equipment,
        cmd_inactive: %ExecCmd{cmd: "off", cmd_opts: [echo: true]},
        programs: ctx[:programs] || :none
      ]
      |> State.new()

    case Enum.into(opts, %{}) do
      %{bootstrap: true} ->
        Server.handle_continue(:bootstrap, new_state)
    end
    |> rationalize(opts)
    |> then(fn state -> %{state: state} end)
  end

  def add(_), do: :ok

  def rationalize(result, opts) do
    cond do
      opts[:raw] == true -> result
      true -> elem(result, 1)
    end
  end
end
