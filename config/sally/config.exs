import Config

config :sally, ecto_repos: [Sally.Repo]

config :sally,
  mqtt_connection: [
    handler:
      {Sally.Mqtt.Handler, [next_actions: [connected: [{:subscribe, "#{config_env()}/r2/#", qos: 0}]]]},
    options: [topic: "#{config_env()}"],
    keep_alive: 36
  ]

config :sally, Sally.Host.Firmware,
  uri: [host: "www.wisslanding.com", path: "sally/firmware", file: "latest-v2.bin"]

config :sally, Sally.Host.Instruct, publish: [prefix: "#{config_env()}", qos: 1]
config :sally, Sally.Message.Handler, msg_mtime_variance_ms: 100_000

if config_env() in [:dev, :test] do
  import_config "test.exs"
  import_config "test-secret.exs"
end
