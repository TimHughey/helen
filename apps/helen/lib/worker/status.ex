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

  def mode_status(state, mode) do
    cond do
      active_mode(state) == mode -> :running
      finished_mode?(state, mode) -> :finished
      true -> :none
    end
  end

  def status(state) do
    clean_action = fn
      :none -> :none
      %{} = x -> Map.take(x, [:cmd, :worker_cmd, :stmt])
    end

    %{
      name: worker_name(state),
      ready: ready?(state),
      status: status_get(state),
      active: %{
        mode: active_mode(state),
        step: active_step(state),
        action: pending_action(state) |> clean_action.()
      },
      modes: all_modes_status(state),
      sub_workers: all_workers_status(state)
    }
  end
end
