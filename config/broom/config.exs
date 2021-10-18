import Config

if Config.config_env() == :test do
  config :broom, ecto_repos: [Broom.Repo]

  config :broom, Broom.Repo,
    username: "broom_test",
    password: "broom_test",
    database: "broom_test",
    port: 15_432,
    hostname: "db.test.wisslanding.com",
    pool_size: 10,
    migration_timestamps: [type: :utc_datetime_usec],
    adapter: Ecto.Adapters.Postgres,
    loggers: [{Ecto.LogEntry, :log, [:debug]}],
    timeout: 5000
end
