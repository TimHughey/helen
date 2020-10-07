defmodule UI.ModuleConfigView do
  use UI, :view

  def button_click(%{"module" => mod_bin}, _socket) do
    parts_bin = String.split(mod_bin, ".")
    base_bin = Enum.drop(parts_bin, -1)

    opts_mod = List.flatten([base_bin, ["Opts"]]) |> Module.concat()

    %{module: mod_bin, opts: opts_as_binary(opts_mod)}
  end

  def opts_as_binary(opts_mod) do
    if function_exported?(opts_mod, :default_opts, 0) do
      case opts_mod.default_opts do
        opts when is_binary(opts) -> opts
        opts -> inspect(opts, pretty: true)
      end
    else
      "not implemented"
    end
  end
end
