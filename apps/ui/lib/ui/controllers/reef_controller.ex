defmodule UI.ReefController do
  use UI, :controller

  # def index(conn, _params) do
  #   reef_state = Reef.x_state()
  #
  #   render(conn, "index.html", reef_state: reef_state)
  # end

  def home(conn, _params) do
    reef_state = Reef.x_state()

    render(conn, "reef_home.html", reef_state: reef_state)
  end
end
