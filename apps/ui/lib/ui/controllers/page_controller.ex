defmodule UI.PageController do
  use UI, :controller

  def index(conn, _params) do
    import Ecto.Changeset, only: [cast: 3]

    reef_state = Reef.x_state()

    render(conn, "index.html", reef_state: reef_state)
  end
end
