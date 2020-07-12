defmodule UI.PageController do
  use UI, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
