# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :rita, Rita,
  username: "helen_dev",
  password: "helen_dev",
  database: "helen_dev",
  port: 15_432,
  hostname: "db.dev.wisslanding.com",
  pool_size: 10,
  migration_timestamps: [type: :utc_datetime_usec],
  adapter: Ecto.Adapters.Postgres
