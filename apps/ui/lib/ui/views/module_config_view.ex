defmodule UI.ModuleConfigView do
  use UI, :view

  def render_module_buttons(all_modules) do
    for {mod, _opts} <- all_modules do
      mod_str = mod_to_str(mod)
      mod_id = mod_to_id(mod)

      button_content = content_tag(:button, mod_str, id: mod_id)
      button_column = content_tag(:div, button_content, class: "column")

      content_tag(:div, button_column, class: "row")
    end
  end

  defp mod_to_str(mod), do: Module.split(mod) |> Enum.join(" ")
  defp mod_to_id(mod), do: Module.split(mod) |> Enum.join("_")
end
