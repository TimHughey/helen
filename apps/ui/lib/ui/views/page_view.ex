defmodule UI.PageView do
  use UI, :view

  def reef_status do
    Reef.x_state()
    |> inspect(pretty: true)
    |> IO.iodata_to_binary()
    |> Phoenix.HTML.Format.text_to_html()
  end

  def reef_state do
    Reef.x_state()
  end

  def build_reef_state do
    %{worker_mode: mode} = state = Reef.x_state()
    display = get_in(state, [mode])

    content_tag :section, class: :row, name: "reef_state" do
      content_tag :table, class: :state_table do
        content_tag :tbody do
          for {k, v} <- display do
            content_tag :tr, class: :state_row do
              [
                content_tag(:td, "#{inspect(k)}" |> html_escape(), class: :state_key),
                content_tag(:td, "#{inspect(v)}" |> html_escape(), class: :state_value)
              ]
            end
          end
        end
      end
    end
  end
end
