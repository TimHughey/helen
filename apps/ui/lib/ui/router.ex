defmodule UI.Router do
  use UI, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :auth_stub
    plug :put_user_token
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", UI do
    pipe_through :browser

    get "/module_opts", ModuleConfigController, :index
    get "/reef/mode/status", ReefController, :show
    get "/reef", ReefController, :index

    get "/roost", RoostController, :index
    get "/", HomeController, :index
    resources "/:next_page", HomeController, only: [:create]
  end

  # Other scopes may use custom stacks.
  # scope "/api", UI do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test, :prod] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: UI.Telemetry
    end
  end

  defp auth_stub(conn, _) do
    assign(conn, :current_user, %{name: "thughey", id: 5000})
  end

  defp put_user_token(conn, _) do
    if current_user = conn.assigns[:current_user] do
      token = Phoenix.Token.sign(conn, "user socket", current_user.id)
      assign(conn, :user_token, token)
    else
      conn
    end
  end
end
