defmodule Lights.Logic do
  @moduledoc false

  defmacro clear_invalid(cmap) do
    import Map, only: [drop: 2]

    quote do
      drop(unquote(cmap), [:invalid, :invalid_log_at])
    end
  end

  defmacro put_active(cmap, bool) do
    quote do
      put_in(unquote(cmap), [:active], unquote(bool))
    end
  end

  defmacro put_invalid_logged(cmap, s) do
    import Lights.Helpers, only: [now: 1]

    quote do
      put_in(unquote(cmap), [:invalid_log_at], now(unquote(s)))
    end
  end

  # (1 of 3) state has :invalid key, do nothing
  def run(%{invalid: _invalid} = s) do
    import Lights.Config, only: [reload_if_needed: 1]

    put_in(s, [:ctrl_maps], []) |> reload_if_needed()
  end

  # (2 of 3) need to build control maps
  def run(%{ctrl_maps: []} = s) do
    import Lights.ControlMap, only: [make_control_maps: 1]

    put_in(s.ctrl_maps, make_control_maps(s)) |> run()
  end

  # (3 of 3) nominal operation
  def run(%{ctrl_maps: cmaps} = s) do
    import Lights.Config, only: [reload_if_needed: 1]

    s = put_in(s.ctrl_maps, []) |> reload_if_needed()

    for %{job: _job, id: _id} = cmap <- cmaps, reduce: s do
      %{ctrl_maps: x} = s ->
        import List, only: [flatten: 1]

        ctrl_maps = [x, run_job_if_valid(cmap, s)] |> flatten

        put_in(s.ctrl_maps, ctrl_maps)
    end
  end

  def run_job_if_valid(cmap, s) do
    import Lights.ControlMap, only: [is_valid?: 1]

    if is_valid?(cmap) do
      fudge_finish_at_if_needed(cmap) |> clear_invalid() |> run_job(s)
    else
      log_job_invalid(cmap, s)
    end
  end

  def run_job(%{start: %{at: start_at}, finish: %{at: finish_at}} = cmap, s) do
    import Timex, only: [between?: 4]
    import Lights.Helpers, only: [now: 1]

    if between?(now(s), start_at, finish_at, inclusive: :start) do
      # IO.puts("keeping #{inspect(cm, pretty: true)}")
      clear_invalid(cmap) |> put_active(true)
    else
      # IO.puts("discarding #{inspect(cm, pretty: true)}")
      put_active(cmap, false)
    end
  end

  def schedule_run(s) do
    import Lights.Helpers, only: [put_in_run: 3, run_interval: 1]
    import Process, only: [send_after: 4]

    t = send_after(self(), :run, run_interval(s), abs: false)

    put_in_run(s, :timer, t)
  end

  #
  # Logging
  #
  def log_job_invalid(cmap, s) do
    put_active(cmap, false) |> put_invalid_logged(s)
  end

  def timeout_hook(s), do: s

  #
  # Private
  #

  defp fudge_finish_at_if_needed(map) do
    if Timex.before?(map.finish.at, map.start.at) do
      map |> put_in([:finish, :at], Timex.shift(map.finish.at, days: 1))
    else
      map
    end
  end
end
