defmodule Helen.Worker.Status do
  @moduledoc false

  import Helen.Worker.State.Common
  import Helen.Worker.State

  def add_ready_status(status, state) do
    import Map, only: [merge: 2]

    if ready?(state) do
      merge(status, %{ready: true})
    else
      merge(status, %{ready: false, not_ready_reason: standby_reason(state)})
    end
  end

  def all_modes_status(state) do
    for mode <- opts_mode_names(state) do
      %{mode: mode, status: mode_status(state, mode)}
    end
  end

  def all_workers_status(state) do
    for {_key, %{module: mod, ident: ident, type: type}}
        when type in [:gen_device, :temp_server] <-
          cached_workers(state) do
      %{
        name: ident,
        ready: mod.ready?(),
        status:
          if type == :gen_device do
            mod.value([:simple])
          else
            mod.position([:simple])
          end
      }
    end
  end

  def make_duration(d) do
    import Helen.Time.Helper, only: [to_binary: 1, to_duration: 1, to_ms: 1]

    if is_binary(d) do
      %{ms: to_ms(to_duration(d)), binary: to_binary(to_duration(d))}
    else
      %{ms: to_ms(d), binary: to_binary(d)}
    end
  end

  def mode_status(state, mode) do
    cond do
      active_mode(state) == mode and status_holding?(state) -> :holding
      active_mode(state) == mode -> :running
      finished_mode?(state, mode) -> :finished
      true -> :none
    end
  end

  def status(state) do
    import Helen.Time.Helper, only: [to_binary: 1]

    %{
      name: worker_name(state),
      status: status_get(state),
      active: %{
        mode: active_mode(state),
        run_for: make_duration(step_run_for(state)),
        elapsed: make_duration(step_elapsed(state)),
        repeating: mode_repeat_until_stopped?(state),
        step: active_step(state),
        action: clean_action(state) |> convert_durations(),
        started_at: step_started_at(state) |> to_binary()
      },
      first_mode: first_mode(state),
      modes: all_modes_status(state),
      sub_workers: all_workers_status(state)
    }
    |> add_ready_status(state)
  end

  def clean_action(state) do
    case pending_action(state) do
      :none ->
        :none

      %{meta: %{run_for: run_for, elapsed: elapsed}} = x ->
        Map.take(x, [:cmd, :for, :then])
        |> put_in([:run_for], run_for)
        |> put_in([:elapsed], elapsed)

      _unmatched ->
        :none
    end
  end

  def convert_durations(:none), do: :none

  def convert_durations(action) do
    for {key, value} when key in [:elapsed, :run_for, :for] <- action,
        reduce: action do
      action -> put_in(action, [key], make_duration(value))
    end
  end
end
