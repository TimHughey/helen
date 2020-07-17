defmodule UI.ReefView do
  use UI, :view

  def subsystem_status(system, subsystem, text) do
    alias Reef.{DisplayTank, MixTank}

    case {system, subsystem} do
      {:mixtank, :air} -> render_subsystem_status(MixTank.Air, text)
      {:mixtank, :pump} -> render_subsystem_status(MixTank.Pump, text)
      {:mixtank, :rodi} -> render_subsystem_status(MixTank.Rodi, text)
      {:mixtank, :heat} -> render_subsystem_status(MixTank.Temp, text)
      {:display_tank, :ato} -> render_ato_subsystem_status(DisplayTank.Ato, text)
      {:display_tank, :heat} -> render_subsystem_status(DisplayTank.Temp, text)
    end
  end

  defp render_subsystem_status(mod, text) do
    active? = apply(mod, :active?, [])

    position = subsystem_position(mod)

    cond do
      active? == true and position == false ->
        content_tag(:div, text, class: "reef-subsystem-ready")

      active? == true and position == true ->
        content_tag(:div, text, class: "reef-subsystem-running")

      apply(mod, :active?, []) == false ->
        content_tag(:div, text, class: "reef-subsystem-standby")
    end
  end

  defp render_ato_subsystem_status(mod, text) do
    active? = apply(mod, :active?, [])

    position = subsystem_position(mod)

    cond do
      active? == true and position == false ->
        content_tag(:div, text, class: "reef-subsystem-ready")

      active? == true and position == true ->
        content_tag(:div, text, class: "reef-subsystem-ato-running")

      apply(mod, :active?, []) == false ->
        content_tag(:div, text, class: "reef-subsystem-standby")
    end
  end

  defp subsystem_position(mod) do
    case apply(mod, :position, []) do
      {:ok, false} -> false
      {:ok, true} -> true
      {:pending, list} -> get_in(list, [:position])
      x -> x
    end
  end

  def build_reef_state(%{worker_mode: mode} = state) do
    display = get_in(state, [mode]) || %{status: :ready}

    for {k, v} <- Map.drop(display, [:opts, :step_devices]) do
      content_tag :div, class: "row reef_state_row" do
        [
          content_tag(:div, humanize_atom(k) |> html_escape(), class: "column reef_state_key"),
          content_tag(:div, humanize_value(k, v) |> html_escape(),
            class: "column reef_state_value"
          )
        ]
      end
    end
  end

  defp humanize_atom(a) do
    parts = Atom.to_string(a) |> String.split("_")

    for p <- parts do
      String.capitalize(p)
    end
    |> Enum.join(" ")
    |> IO.iodata_to_binary()
    |> html_escape()
  end

  defp humanize_value(k, v) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case k do
      k when k in [:elapsed, :started_at, :will_finish_by] ->
        to_binary(v)

      :cycles ->
        content_tag(
          :ul,
          for {ck, cv} <- v do
            content_tag(:li, "#{Atom.to_string(ck)}: #{inspect(cv)}",
              class: "reef_state_cycle_item"
            )
          end,
          class: "reef_state_cycle_list"
        )

      _k when is_atom(v) ->
        Atom.to_string(v)

      _k ->
        inspect(v)
    end
  end

  def worker_mode(%{worker_mode: mode}) do
    content_tag(:div, humanize_atom(mode), class: "column")
  end
end
