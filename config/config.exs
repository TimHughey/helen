# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configures Elixir's Logger
config :logger,
  # console: [metadata: [:module], format: "$time $metadata$message\n"],
  console: [format: "$time $message\n"],
  backends: [:console],
  level: :info,
  metadata: [:request_id],
  compile_time_purge_matching: [
    [application: :helen, level_lower_than: :info],
    [application: :swarm, level_lower_than: :error]
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

import_config "helen/config.exs"
import_config "ui/config.exs"
