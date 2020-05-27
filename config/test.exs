# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :helen,
  feeds: [
    prefix: "test",
    rpt: {"prod/r/#", 0}
  ]

config :helen,
  # overrides from config.exs
  worker_supervisors: [
    # DynamicSupervisors
    {Dutycycle.Supervisor, [start_workers: false]},
    {Thermostat.Supervisor, [start_workers: false]}
  ]

config :helen, Janitor.Supervisor, log: [init: false, init_args: false]

config :helen, Janitor,
  log: [dryrun: false, init: false, init_args: false],
  metrics_frequency: [orphan: [minutes: 5], switch_cmd: [minutes: 5]]

config :helen, Mqtt.Client,
  log_dropped_msg: true,
  runtime_metrics: true,
  tort_opts: [
    client_id: "helen-test",
    user_name: "mqtt",
    password: "mqtt",
    server:
      {Tortoise.Transport.Tcp, host: "mqtt.test.wisslanding.com", port: 1883},
    keep_alive: 15
  ],
  timesync: [frequency: {:secs, 5}, loops: 5, forever: false, log: false]

config :helen, Mqtt.Inbound,
  log: [
    engine_metrics: false
  ],
  periodic_log: [enable: false, first: {:secs, 10}, repeat: {:mins, 5}]

config :helen, Fact.Influx,
  database: "helen_test",
  host: "influx.test.wisslanding.com",
  auth: [method: :basic, username: "helen_test", password: "helen_test"],
  http_opts: [insecure: true],
  pool: [max_overflow: 10, size: 10, timeout: 60_000, max_connections: 30],
  port: 8086,
  scheme: "http",
  writer: Instream.Writer.Line

config :helen, PulseWidthCmd,
  orphan: [
    at_startup: true,
    sent_before: [seconds: 1],
    log: true
  ],
  purge: [
    at_startup: false,
    interval: [minutes: 2],
    older_than: [days: 30],
    log: true
  ]

config :helen, Repo,
  username: "helen_test",
  password: "helen_test",
  database: "helen_test",
  port: 15432,
  hostname: "db.test.wisslanding.com",
  pool_size: 10,
  migration_timestamps: [type: :utc_datetime_usec],
  adapter: Ecto.Adapters.Postgres

config :helen, Switch.Command,
  log: [dryrun: false],
  # NOTE:  Timex.shift/2 is used to convert sent_before into a UTC Datetime
  orphan: [
    at_startup: true,
    sent_before: [seconds: 1],
    log: true
  ],
  purge: [
    at_startup: true,
    schedule: {:extended, "33 */3 * * *"},
    older_than: [days: 30],
    log: true
  ]

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
