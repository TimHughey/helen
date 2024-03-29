import Config

config :sally, ecto_repos: [Sally.Repo]

config :sally,
  mqtt_connection: [
    handler:
      {Sally.Mqtt.Handler, [next_actions: [connected: [{:subscribe, "#{config_env()}/r2/#", qos: 0}]]]},
    options: [topic: "#{config_env()}"],
    keep_alive: 36,
    filter_env: "#{config_env()}"
  ]

# config :sally, Sally.Host,
#   host_profiles: [dir: :auto, search_paths: [".", "/usr/local/helen_v2/etc", "test/toml", "etc"]]

config :sally, Sally.Host.Firmware,
  opts: [
    search_paths: ["/dar/www/wisslanding/htdocs/sally", "."],
    dir: "firmware",
    file_regex: ~r/\d\d\.\d\d\.\d\d.+-ruth\.bin$/
  ]

config :sally, Sally.Host.Instruct, publish: [prefix: "#{config_env()}"]

if config_env() in [:dev, :test] do
  import_config "#{config_env()}.exs"
  import_config "#{config_env()}-secret.exs"
  #  import_config "#{config_env()}-localhost-secret.exs"
end

if config_env() == :prod do
  import_config "#{config_env()}.exs"
  import_config "#{config_env()}-secret.exs"
end
