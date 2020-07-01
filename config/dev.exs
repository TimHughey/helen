# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :helen,
  feeds: [
    prefix: "dev",
    rpt: {"prod/r/#", 0}
  ]

config :helen, Mqtt.Client,
  log_dropped_msgs: true,
  tort_opts: [
    client_id: "helen-dev",
    user_name: "mqtt",
    password: "mqtt",
    server:
      {Tortoise.Transport.Tcp, host: "mqtt.test.wisslanding.com", port: 1883},
    keep_alive: 15
  ]

config :helen, Mqtt.Inbound,
  log: [
    engine_metrics: false
  ]

config :helen, Fact.Influx,
  database: "helen_dev",
  host: "influx.dev.wisslanding.com",
  auth: [method: :basic, username: "helen_dev", password: "helen_dev"],
  http_opts: [insecure: true],
  pool: [max_overflow: 10, size: 10, timeout: 60_000, max_connections: 30],
  port: 8086,
  scheme: "http",
  writer: Instream.Writer.Line

config :helen, PulseWidth.DB.Command,
  orphan: [
    startup_check: true,
    sent_before: "PT1S"
  ],
  purge: [
    at_startup: false,
    interval: "PT2M",
    older_than: "PT10D"
  ],
  metrics: "PT1M"

config :helen, Repo,
  username: "helen_dev",
  password: "helen_dev",
  database: "helen_dev",
  port: 15432,
  hostname: "db.dev.wisslanding.com",
  pool_size: 10,
  migration_timestamps: [type: :utc_datetime_usec],
  adapter: Ecto.Adapters.Postgres

config :helen, Switch.DB.Command,
  # NOTE:  Timex.shift/2 is used to convert sent_before into a UTC Datetime
  orphan: [
    at_startup: true,
    sent_before: "PT1S"
  ],
  purge: [
    at_startup: true,
    interval: "PT1M",
    older_than: "PT1D"
  ],
  metrics: "PT1M"

config :helen, Helen.Scheduler,
  global: true,
  run_strategy: Quantum.RunStrategy.Local,
  timezone: "America/New_York",
  jobs: [
    # Every minute
    {:touch,
     [
       schedule: {:extended, "* * * * *"},
       task: {Jobs, :touch_file, ["/tmp/helen-dev.touch"]},
       run_strategy: Quantum.RunStrategy.Local
     ]}
  ]
