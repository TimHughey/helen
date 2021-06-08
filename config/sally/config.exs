import Config

config :sally, ecto_repos: [Sally.Repo]

config :sally,
  mqtt_connection: [
    handler: {Sally.Mqtt.Handler, [next_actions: [connected: [{:subscribe, "#{config_env()}/r/#", qos: 0}]]]},
    options: [topic: "#{config_env()}"],
    keep_alive: 36
  ]

config :sally, Sally.Host.Reply, publish: [prefix: "#{config_env()}", qos: 1]
config :sally, Sally.MsgOut, publish: [prefix: "#{config_env()}", qos: 1]
#  runtime_metrics: [all: false]

config :sally, Sally.Message.Handler, msg_old_ms: 5_000
# route_to: Sally.MsgIn.Processor

# config :sally, Sally.MsgIn,
#   msg_old_ms: 5_000,
#   routing: [
#     {:pwm, Sally.PulseWidth.MsgHandler},
#     {:switch, Sally.Switch},
#     {:sensor, Sally.Sensor},
#     {:rhost, Sally.Remote}
#   ]

if config_env() in [:dev, :test] do
  import_config "test-secret.exs"
end
