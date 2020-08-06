defmodule UI.ModuleConfigController do
  use UI, :controller

  def index(conn, _params) do
    conn
    |> put_session(:active_page, "module_config")
    |> render("index.html")
  end
end
