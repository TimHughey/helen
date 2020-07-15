defmodule UI.PageView do
  use UI, :view

  def reef_status do
    alias Phoenix.HTML.Format

    Reef.x_state()
    |> inspect(pretty: true)
    |> IO.iodata_to_binary()
    |> Format.text_to_html()
  end

  def reef_state do
    Reef.x_state()
  end

  def build_reef_state do
    %{worker_mode: mode} = state = Reef.x_state()
    display = get_in(state, [mode]) || %{status: :ready}

    for {k, v} <- Map.drop(display, [:opts, :step_devices]) do
      content_tag :div, class: "row reef_state_row" do
        [
          content_tag(:div, humanize_key(k) |> html_escape(), class: "column reef_state_key"),
          content_tag(:div, humanize_value(k, v) |> html_escape(),
            class: "column reef_state_value"
          )
        ]
      end
    end
  end

  defp humanize_key(k) do
    Atom.to_string(k)
  end

  defp humanize_value(k, v) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case k do
      k when k in [:elapsed, :started_at, :will_finish_by] -> to_binary(v)
      _k when is_atom(v) -> Atom.to_string(v)
      _k -> inspect(v)
    end
  end

  def worker_mode do
    %{worker_mode: mode} = Reef.x_state()

    parts = Atom.to_string(mode) |> String.split("_")

    for p <- parts do
      String.capitalize(p)
    end
    |> Enum.join(" ")
    |> IO.iodata_to_binary()
    |> html_escape()
  end
end
