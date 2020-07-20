defmodule UI.ReefView do
  use UI, :view

  alias Reef.{DisplayTank, MixTank}

  def render_step_details(%{worker_mode: mode} = state) do
    import Helen.Time.Helper, only: [remaining: 2, to_binary: 1, to_duration: 1]

    active_step = get_in(state, [mode, :active_step])
    steps_remaining = get_in(state, [mode, :steps_to_execute])
    step = get_in(state, [mode, :step])
    cmd = get_in(step, [:cmd])

    {_cmd, cmd_opts} = get_in(step, [:next_cmd])
    cmd_for = get_in(cmd_opts, [:for]) |> to_duration()

    cmd_started_at = get_in(step, [:started_at])
    cmd_remaining = remaining(cmd_started_at, cmd_for)

    cmds_to_execute = get_in(step, [:cmds_to_execute])

    [
      content_tag(:div, humanize_atom_safe(active_step), class: "column"),
      content_tag(:div, render_step_name_list(steps_remaining), class: "column"),
      content_tag(:div, humanize_atom_safe(cmd), class: "column"),
      content_tag(:div, to_binary(cmd_remaining), class: "column"),
      content_tag(:div, inspect(cmds_to_execute), class: "column")
    ]
  end

  def render_step_name_list(step_names) do
    step_names_list =
      for name <- step_names do
        content_tag(:li, humanize_atom(name), class: "reef-steps-remaining")
      end

    content_tag(:ul, step_names_list)
  end

  def render_subsystem_status(mod, text) do
    active? = apply(mod, :active?, [])

    position = subsystem_position(mod)

    cond do
      active? == true ->
        render_subsystem_active_status(mod, text, position)

      active? == false ->
        content_tag(:div, text, class: "reef-subsystem-standby")

      true ->
        content_tag(:div, text, class: "reef-subsystem-nomatch")
    end
  end

  def render_subsystem_active_status(mod, text, position) do
    cond do
      position == false ->
        content_tag(:div, text, class: "reef-subsystem-ready")

      position == true and mod == DisplayTank.Ato ->
        content_tag(:div, text, class: "reef-subsystem-ato-running")

      position == true ->
        content_tag(:div, text, class: "reef-subsystem-running")

      true ->
        content_tag(:div, text, class: "reef-subsystem-nomatch")
    end
  end

  def render_worker_modes_status(state) do
    modes = Reef.available_worker_modes()

    for mode <- modes, {k, %{status: val}} when k == mode <- state do
      mode_content = render_worker_mode_status(humanize_atom_safe(k), val)

      content_tag(:div, mode_content, class: "column reef-worker-mode-status")
    end
  end

  def render_worker_mode_status(mode_str, val) do
    case val do
      :ready -> content_tag(:div, mode_str, class: "reef-worker-mode-ready")
      :running -> content_tag(:div, mode_str, class: "reef-worker-mode-running")
      :finished -> content_tag(:div, mode_str, class: "reef-worker-mode-finished")
      _val -> content_tag(:div, mode_str, class: "reef-worker-mode-unknown")
    end
  end

  def render_worker_mode_summary(%{worker_mode: mode} = state) do
    import Helen.Time.Helper, only: [to_binary: 1]

    %{started_at: started_at, elapsed: elapsed, active_step: active_step} = get_in(state, [mode])

    will_finish_by = get_in(state, [mode, :will_finish_by])
    num_cycles = get_in(state, [mode, :cycles, active_step])

    [
      content_tag(:div, to_binary(started_at), class: "column"),
      (will_finish_by && content_tag(:div, to_binary(will_finish_by), class: "column")) ||
        content_tag(:div, "When Stopped", class: "column"),
      content_tag(:div, to_binary(elapsed), class: "column"),
      content_tag(:div, remaining_time(state, mode), class: "column"),
      content_tag(:div, humanize_atom_safe(active_step), class: "column"),
      content_tag(:div, Integer.to_string(num_cycles), class: "column")
    ]
  end

  defp remaining_time(state, mode) do
    import Helen.Time.Helper, only: [remaining: 1, to_binary: 1]

    case get_in(state, [mode, :will_finish_by]) do
      nil -> "Infinity"
      x when is_struct(x) -> remaining(x) |> to_binary()
      _x -> "Unknown"
    end
  end

  # def render_worker_mode_details(%{worker_mode: mode} = state) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   %{steps_to_execute: steps_to_execute, step: step, sub_steps: sub_steps} =
  #     get_in(state, [mode])
  #
  #   [
  #     content_tag(:pre, inspect(steps_to_execute), class: "column"),
  #     content_tag(:pre, inspect(step, pretty: true), class: "column"),
  #     content_tag(:pre, inspect(sub_steps, pretty: true), class: "column")
  #   ]
  # end

  def render_worker_mode_steps(%{worker_mode: mode} = state) do
    %{steps: steps} = get_in(state, [mode])

    [
      content_tag(:pre, inspect(steps, pretty: true, width: 0), class: "column")
    ]
  end

  defp subsystem_position(mod) do
    case apply(mod, :position, []) do
      {:ok, false} -> false
      {:ok, true} -> true
      {:pending, list} -> get_in(list, [:position])
      x -> x
    end
  end

  # def build_reef_state(%{worker_mode: mode} = state) do
  #   display = get_in(state, [mode]) || %{status: :ready}
  #
  #   for {k, v} <- Map.drop(display, [:opts, :step_devices]) do
  #     content_tag :div, class: "row reef_state_row" do
  #       [
  #         content_tag(:div, humanize_atom_safe(k) |> html_escape(), class: "column reef_state_key"),
  #         content_tag(:div, humanize_value(k, v) |> html_escape(),
  #           class: "column reef_state_value"
  #         )
  #       ]
  #     end
  #   end
  # end

  defp humanize_atom(a) do
    parts = Atom.to_string(a) |> String.split("_")

    for p <- parts do
      String.capitalize(p)
    end
    |> Enum.join(" ")
    |> IO.iodata_to_binary()
  end

  defp humanize_atom_safe(a) do
    humanize_atom(a)
    |> html_escape()
  end

  # defp humanize_value(k, v) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   case k do
  #     k when k in [:elapsed, :started_at, :will_finish_by] ->
  #       to_binary(v)
  #
  #     :cycles ->
  #       content_tag(
  #         :ul,
  #         for {ck, cv} <- v do
  #           content_tag(:li, "#{Atom.to_string(ck)}: #{inspect(cv)}",
  #             class: "reef_state_cycle_item"
  #           )
  #         end,
  #         class: "reef_state_cycle_list"
  #       )
  #
  #     _k when is_atom(v) ->
  #       Atom.to_string(v)
  #
  #     _k ->
  #       inspect(v)
  #   end
  # end

  def worker_mode(%{worker_mode: mode}) do
    content_tag(:div, humanize_atom_safe(mode), class: "column")
  end
end
