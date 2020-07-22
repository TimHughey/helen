defmodule UI.RoostView do
  use UI, :view

  alias Roost.Server

  def render_worker_modes_status(state) do
    modes = Server.available_modes()

    for mode <- modes, {k, %{status: val}} when k == mode <- state do
      mode_content = render_worker_mode_status(k, val)

      content_tag(:div, mode_content, class: "column roost-worker-mode-status")
    end
  end

  def render_worker_mode_status(mode, val) do
    mode_str = humanize_atom_safe(mode)

    case val do
      val when val in [:ready] ->
        content_tag(:button, mode_str,
          class: "roost roost-worker-mode-ready",
          id: worker_mode_id(mode),
          value: Atom.to_string(mode)
        )

      :running ->
        content_tag(:button, mode_str,
          class: "reef roost-worker-mode-running",
          id: worker_mode_id(mode),
          value: Atom.to_string(mode)
        )

      :finished ->
        content_tag(:button, mode_str,
          class: "reef roost-worker-mode-finished",
          id: worker_mode_id(mode),
          value: Atom.to_string(mode)
        )

      val ->
        IO.puts("worker_mode_status: #{inspect(val)}")

        content_tag(:button, mode_str,
          class: "reef roost-worker-mode-unknown",
          id: worker_mode_id(mode),
          value: Atom.to_string(mode)
        )
    end
  end

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

  def worker_mode_id(mode), do: ["roost_mode", Atom.to_string(mode)] |> Enum.join("-")

  def worker_mode(%{worker_mode: mode}) do
    content_tag(:div, humanize_atom_safe(mode), class: "column")
  end
end
