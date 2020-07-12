# This file is responsible for configuring your application
ˇ
# and its dependencies with the aid of the Mix.Config module.
import Config

config :helen,
  feeds: [
    prefix: "test",
    rpt: {"prod/r/#", 0}
  ]

config :helen, Mqtt.Client,
  log_dropped_msg: true,
  runtime_metrics: true,
  tort_opts: [
    client_id: "helen-test",
    user_name: "mqtt",
    password: "mqtt",
    server:
      {Tortoise.Transport.Tcp, host: "mqtt.test.wisslanding.com", port: 1883},
    keep_alive: 36
  ]

config :helen, Mqtt.Inbound,
  log: [
    engine_metrics: false
  ]

# ],
# periodic_log: [enable: false, first: {:secs, 10}, repeat: {:mins, 5}]

config :helen, Fact.Influx,
  database: "helen_test",
  host: "influx.test.wisslanding.com",
  auth: [method: :basic, username: "helen_test", password: "helen_test"],
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
  username: "helen_test",
  password: "helen_test",
  database: "helen_test",
  port: 15432,
  hostname: "db.test.wisslanding.com",
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
       task: {Jobs, :touch_file, ["/tmp/helen-test.touch"]},
       run_strategy: Quantum.RunStrategy.Local
     ]}

    # EXAMPLES:
    #
    # Every 15 minutes
    # {"*/15 * * * *",   fn -> System.cmd("rm", ["/tmp/tmp_"]) end},
    # Runs on 18, 20, 22, 0, 2, 4, 6:
    # {"0 18-6/2 * * *", fn -> :mnesia.backup('/var/backup/mnesia') end},
    # Runs every midnight:
    # {"@daily",         {Backup, :backup, []}}
  ]
