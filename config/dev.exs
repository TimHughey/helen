# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :helen,
  feeds: [
    prefix: "dev",
    rpt: {"prod/r/#", 0}
  ]

config :helen, Mqtt.Client,
  log_dropped_msg: true,
  runtime_metrics: true,
  tort_opts: [
    client_id: "helen-dev",
    user_name: "mqtt",
    password: "mqtt",
    server:
      {Tortoise.Transport.Tcp, host: "mqtt.test.wisslanding.com", port: 1883},
    keep_alive: 36
  ],
  timesync: [frequency: {:secs, 5}, loops: 5, forever: false, log: false]

config :helen, Mqtt.Inbound,
  log: [
    engine_metrics: false
  ]

# ],
# periodic_log: [enable: false, first: {:secs, 10}, repeat: {:mins, 5}]

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
    sent_before: [seconds: 1]
  ],
  purge: [
    at_startup: false,
    interval: [minutes: 2],
    older_than: [days: 30]
  ],
  metrics: [minutes: 1]

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
    sent_before: [seconds: 1]
  ],
  purge: [
    at_startup: true,
    schedule: {:extended, "33 */3 * * *"},
    older_than: [days: 1]
  ],
  metrics: [minutes: 1]

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

    # EXAMPLES:
    #
    # Every 15 minutes
    # {"*/15 * * * *",   fn -> System.cmd("rm", ["/tmp/tmp_"]) end},
    # Runs on 18, 20, 22, 0, 2, 4, 6:
    # {"0 18-6/2 * * *", fn -> :mnesia.backup('/var/backup/mnesia') end},
    # Runs every midnight:
    # {"@daily",         {Backup, :backup, []}}
  ]
