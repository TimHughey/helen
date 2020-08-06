defmodule UI.ReefController do
  use UI, :controller

  def index(conn, _params) do
    conn
    |> put_session(:active_page, "reef")
    |> render("index.html")
  end
end
