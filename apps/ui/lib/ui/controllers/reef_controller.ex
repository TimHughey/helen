defmodule UI.ReefController do
  use UI, :controller

  def index(conn, _params) do
    conn
    |> put_session(:active_page, "reef")
    |> render("index.html")
  end

  def show(conn, %{"mode" => mode}) do
    conn
    |> Plug.Conn.assign(:mode, mode)
    |> render("status.html")
  end
end
