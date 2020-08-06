defmodule UI.RoostController do
  use UI, :controller

  def index(conn, _params) do
    conn
    |> put_session(:active_page, "roost")
    |> render("index.html")
  end
end
