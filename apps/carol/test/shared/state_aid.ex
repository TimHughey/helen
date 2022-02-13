defmodule Carol.StateAid do
  @moduledoc false

  @tz "America/New_York"

  def add(%{} = ctx) do
    episodes = ctx[:episodes] || []
    ctx_opts = ctx[:opts] || [alfred: AlfredSim, timezone: @tz, ref_dt: Timex.now(@tz)]

    case ctx do
      %{state_add: state_opts} ->
        all_opts = state_opts ++ [episodes: episodes, opts: ctx_opts]
        add(all_opts)

      _ ->
        :ok
    end
  end

  def add([_ | _] = opts) do
    alfred = opts[:alfred] || AlfredSim
    equip_opts = opts[:equipment] || []
    dev_alias = Alfred.NamesAid.new_dev_alias(:equipment, equip_opts)

    fields = [
      opts: [alfred: alfred, timezone: @tz],
      id: opts[:server_name] || __MODULE__,
      instance: Alfred.NamesAid.unique("carol"),
      equipment: dev_alias.name,
      episodes: opts[:episodes] || :none
    ]

    new_state = Carol.State.new(fields)

    case Enum.into(opts, %{}) do
      %{tick: true} -> handle_continues(new_state, [:bootstrap, :tick])
      %{bootstrap: true} -> handle_continues(new_state, [:bootstrap])
      _ -> new_state
    end
    |> rationalize(opts)
    |> then(fn state -> %{state: state, dev_alias: dev_alias} end)
  end

  def handle_continues(state, steps) do
    Enum.reduce(steps, state, &invoke_handle_continue(&1, &2))
  end

  def invoke_handle_continue(step, state_or_tuple) do
    case state_or_tuple do
      %{} = state -> state
      {_, state} -> state
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
