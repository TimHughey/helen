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

    # content_tag :section, class: :row, name: "reef_state" do
    #   content_tag :table, class: :steelBlueCols do
    #     content_tag :tbody do
    for {k, v} <- display do
      content_tag :div, class: "row reef_state_row" do
        [
          content_tag(:div, "#{Atom.to_string(k)}" |> html_escape(),
            class: "column reef_state_key"
          ),
          content_tag(:div, "#{inspect(v)}" |> html_escape(), class: "column reef_state_value")
        ]
      end

      #     end
      #   end
      # end
    end
  end
end
