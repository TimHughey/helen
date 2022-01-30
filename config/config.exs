# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

# local_secrets = [System.user_home(), "devel", "shell", "local"]

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configures Elixir's Logger
config :logger,
  console: [format: "$level$levelpad $time $metadata$message\n", metadata: [:mfa, :line]],
  backends: [:console],
  level: :info,
  compile_time_purge_matching: [[application: :helen, level_lower_than: :info]]

apps = ["betty", "carol", "farm", "glow", "sally", "legacy_db"]

Enum.each(apps, fn app -> import_config "#{app}/config.exs" end)
