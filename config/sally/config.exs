import Config

config :sally, ecto_repos: [SallyRepo]

config :sally,
  mqtt_connection: [
    handler: {Sally.Mqtt.Handler, [next_actions: [connected: [{:subscribe, "#{config_env()}/r/#", qos: 0}]]]},
    options: [topic: "#{config_env()}"],
    keep_alive: 36
  ]

config :sally, Sally.Mqtt.Client,
  publish: [prefix: "#{config_env()}", qos: 1],
  runtime_metrics: [all: false]

config :sally, Sally.InboundMsg.Server,
  msg_routing: [
    {"pwm", Sally.PulseWidth},
    {"switch", Sally.Switch},
    {"sensor", Sally.Sensor},
    {"remote", Sally.Remote}
  ]

if config_env() in [:dev, :test] do
  import_config "test-secret.exs"
end
