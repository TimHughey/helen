defmodule Helen.Worker.Status do
  @moduledoc false

  import Helen.Worker.State.Common
  import Helen.Worker.State

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
    import Helen.Time.Helper, only: [to_binary: 1, to_ms: 1]

    %{ms: to_ms(d), binary: to_binary(d)}
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

    clean_action = fn
      :none ->
        :none

      %{meta: %{run_for: run_for, elapsed: elapsed}} = x ->
        Map.take(x, [:cmd, :worker_cmd, :stmt])
        |> put_in([:run_for], make_duration(run_for))
        |> put_in([:elapsed], make_duration(elapsed))
    end

    %{
      name: worker_name(state),
      ready: ready?(state),
      status: status_get(state),
      active: %{
        mode: active_mode(state),
        run_for: make_duration(step_run_for(state)),
        elapsed: make_duration(step_elapsed(state)),
        repeating: mode_repeat_until_stopped?(state),
        step: active_step(state),
        action: pending_action(state) |> clean_action.(),
        started_at: step_started_at(state) |> to_binary()
      },
      first_mode: first_mode(state),
      modes: all_modes_status(state),
      sub_workers: all_workers_status(state)
    }
  end
end
