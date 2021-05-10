# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :logger,
  # console: [metadata: [:module], format: "$time $metadata$message\n"],
  # console: [format: "$date $time $message\n"],
  console: [format: ">>$level$levelpad $time $metadata$message\n", metadata: [:mfa, :line]],
  backends: [:console],
  level: :info,
  metadata: [:request_id],
  compile_time_purge_matching: [
    [application: :helen, level_lower_than: :debug]
  ]

# reference for the config in secret.exs
config :ruth_sim, :topic, prefix: "test"
config :ruth_sim, :default_tz, "America/New_York"

config :ruth_sim, MqttHandler,
  next_actions: [
    connected: [{:subscribe, "test/#", qos: 1}]
  ]

# must create a soft link to the secrets config

import_config "secret.exs"
