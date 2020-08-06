defmodule UI.ReefController do
  use UI, :controller

  # def index(conn, _params) do
  #   reef_state = Reef.x_state()
  #
  #   render(conn, "index.html", reef_state: reef_state)
  # end

  def home(conn, _params) do
    reef_state = Reef.x_state()

    conn
    |> put_session(:active_page, "reef")
    |> render("reef_home.html", reef_state: reef_state, active_page: "reef")
  end
end
