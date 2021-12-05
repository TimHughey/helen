defmodule Carol.StateAid do
  alias Alfred.ExecCmd
  alias Carol.{Server, State}

  @doc """
  Add %State{} to testing context

  State fields set by default: `:alfred, :server_name, :equipment, :schedules`

  ```
  # run handle_continue(:bootstrap, state), return noreply
  %{schedule_add: [bootstrap: true, raw: true]}
  |> add()
  #=> %{state: new_state}


  ```



  Options


  """

  # def add(%{equipment: equipment, state_add: []} = ctx) do
  #   %State{
  #     alfred: AlfredSim,
  #     server_name: ctx.server_name,
  #     equipment: %Ticket{name: equipment, ref: make_ref()},
  #     result: %Result{schedule: %Schedule{start: %Point{cmd: %ExecCmd{cmd: "on"}}}, action: :live}
  #   }
  #   |> then(fn state -> %{state: state} end)
  # end

  def add(%{state_add: opts} = ctx) when is_list(opts) do
    alfred = ctx[:alfred] || AlfredSim
    server_name = ctx[:server_name] || __MODULE__
    equipment = ctx[:equipment] || "equipment missing"
    schedules = ctx[:schedules] || []

    new_state =
      [
        alfred: alfred,
        server_name: server_name,
        equipment: equipment,
        cmd_inactive: %ExecCmd{cmd: "off", cmd_opts: [echo: true]},
        schedules: schedules
      ]
      |> State.new()

    case Enum.into(opts, %{}) do
      %{bootstrap: true} ->
        Server.handle_continue(:bootstrap, new_state)

      %{schedule: true} ->
        Server.handle_continue(:bootstrap, new_state)
        |> then(fn noreply -> Server.handle_info(:schedule, elem(noreply, 1)) end)
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
