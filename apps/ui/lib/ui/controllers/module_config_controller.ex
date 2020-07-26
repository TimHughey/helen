defmodule UI.ModuleConfigController do
  use UI, :controller

  def home(conn, _params) do
    alias Helen.Module.Config

    all_modules = Config.all()

    render(conn, "home.html", modules: all_modules)
  end
end
