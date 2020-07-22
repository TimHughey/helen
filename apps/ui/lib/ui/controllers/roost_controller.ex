defmodule UI.RoostController do
  use UI, :controller

  alias Roost.Server

  # def index(conn, _params) do
  #   reef_state = Reef.x_state()
  #
  #   render(conn, "index.html", reef_state: reef_state)
  # end

  def home(conn, _params) do
    roost_state = Server.x_state()

    render(conn, "roost_home.html", roost_state: roost_state)
  end
end
