defmodule UI.ReefController do
  use UI, :controller

  plug :put_layout, false when action in [:show]

  require Logger

  def index(conn, _params) do
    conn
    |> put_session(:active_page, "reef")
    |> render("index.html", Reef.status())
  end

  def show(conn, %{"worker" => "captain"}) do
    status = Reef.status() |> get_in([:workers, :captain])

    render(conn, "captain_mode_status.html", status)
  end

  def show(conn, %{"worker" => worker, "active_mode" => _active_mode} = params) do
    render(conn, "#{worker}_mode_status.html", params)
  end
end
