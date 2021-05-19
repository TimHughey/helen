import Config

config :rita, Rita,
  username: "helen_test",
  password: "helen_test",
  database: "helen_test",
  port: 15_432,
  hostname: "db.test.wisslanding.com",
  pool_size: 10,
  migration_timestamps: [type: :utc_datetime_usec],
  adapter: Ecto.Adapters.Postgres,
  loggers: [{Ecto.LogEntry, :log, [:debug]}],
  timeout: 5000
