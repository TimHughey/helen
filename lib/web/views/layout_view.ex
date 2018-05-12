defmodule Web.LayoutView do
  use Web, :view

  require Logger

  def locate_ui_files do
    bundles_path = Application.app_dir(:mcp, "priv/static/bundles")

    {:ok, files} = File.ls(bundles_path)
    Logger.warn(fn -> inspect(files, pretty: true) end)

    # styles_re = ~r/(?<file>styles\.[[:xdigit]]+\.bundle\.css)/
    styles_re = ~r/styles.[[:xdigit]]+.bundle.css$/
    js_re = ~r/[a-z]+.[[:xdigit:]]+.bundle.js$/

    ss = for f <- files, Regex.match?(styles_re, f), do: f

    js = for f <- files, Regex.match?(js_re, f), do: f

    Logger.warn(fn -> inspect(ss, pretty: true) end)
    Logger.warn(fn -> inspect(js, pretty: true) end)

    %{ss: ss, js: js}
  end

  def ui_js_files do
    # files = ["inline", "polyfills", "styles", "vendor", "main"]
    files = ["inline", "polyfills", "main"]
    # env = "#{Mix.env()}"

    # if env === "dev" or env === "test" do
    #   for f <- files, do: "#{f}.bundle.js"
    # else
    %{ss: _, js: js_files} = locate_ui_files()

    for f <- files do
      Enum.find(js_files, fn x -> String.contains?(x, f) end)
    end

    # end
  end

  def stylesheets do
    locate_ui_files() |> Map.get(:ss, [])
  end

  def javascripts do
    [inline_js(), polyfills_js(), main_js()]
  end

  def inline_js do
    locate_ui_files() |> Map.get(:js, []) |> Enum.find(fn x -> String.match?(x, ~r/inline/) end)
  end

  def main_js do
    locate_ui_files() |> Map.get(:js, []) |> Enum.find(fn x -> String.match?(x, ~r/main/) end)
  end

  def polyfills_js do
    locate_ui_files() |> Map.get(:js, []) |> Enum.find(fn x -> String.match?(x, ~r/polyfill/) end)
  end

  def bundle_file(conn, file) do
    static_path(conn, "/bundles/#{file}")
  end
end
