defmodule UI.HomeController do
  use UI, :controller

  def index(%{request_path: _request_path} = conn, _params) do
    # conn |> get_session() |> inspect(pretty: true) |> IO.puts()
    # request_path |> inspect(pretty: true) |> IO.puts()

    auto_refresh = get_session(conn, :auto_refresh) || false

    render(conn, "index.html", live_update: auto_refresh)
  end

  def create(conn, %{"auto_refresh" => auto_refresh}) do
    new_auto_refresh =
      case auto_refresh do
        "false" -> false
        "true" -> true
      end

    conn
    |> put_session(:auto_refresh, new_auto_refresh)
    |> configure_session(renew: true)

    # |> put_flash(
    #   :info,
    #   ["new auto refresh: ", inspect(new_auto_refresh)] |> IO.iodata_to_binary()
    # )
    |> redirect(external: get_req_header(conn, "referer") |> hd())
  end

  def create(conn, %{"next_page" => next_page} = params) do
    IO.puts("conn: #{inspect(conn, pretty: true)} \n params: #{inspect(params, pretty: true)}")

    conn
    |> put_session(:active_page, next_page)
    |> redirect(to: "/#{next_page}")
  end
end
