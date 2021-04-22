# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :agnus,
  day_info: [cache_file: "priv/agnus.json"]

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :helen, :default_tz, "America/New_York"

# Configures Elixir's Logger
config :logger,
  # console: [metadata: [:module], format: "$time $metadata$message\n"],
  # console: [format: "$date $time $message\n"],
  console: [format: "::$level$levelpad $time $metadata$message\n", metadata: [:mfa, :line]],
  backends: [:console],
  level: :info,
  metadata: [:request_id],
  compile_time_purge_matching: [
    [application: :helen, level_lower_than: :info]
  ]

import_config "garden/config.exs"
import_config "helen/config.exs"
import_config "ui/config.exs"
