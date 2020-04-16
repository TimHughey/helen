# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :helen,
  feeds: [
    cmd: {"test/mcr/f/command", 1},
    rpt: {"prod/mcr/f/report", 0}
  ]

config :helen,
  # overrides from config.exs
  worker_supervisors: [
    # DynamicSupervisors
    {Dutycycle.Supervisor, [start_workers: false]},
    {Thermostat.Supervisor, [start_workers: false]}
  ]

#
# NOTE: uncomment to enable saving/forwarding of messages sent and/or
#       recv'd via MQTT
#
# import_config "modules/msg_save_enable.exs"
import_config "modules/msg_save_forward.exs"

config :helen, Mqtt.Client,
  log_dropped_msg: true,
  runtime_metrics: true,
  tort_opts: [
    client_id: "helen-test",
    user_name: "mqtt",
    password: "mqtt",
    server:
      {Tortoise.Transport.Tcp, host: "jophiel.wisslanding.com", port: 1883},
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
  host: "jophiel.wisslanding.com",
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
    at_startup: true,
    interval: [minutes: 2],
    older_than: [days: 30],
    log: true
  ]

config :helen, Repo,
  username: "helen_test",
  password: "helen_test",
  database: "helen_test",
  port: 15432,
  hostname: "test.db.wisslanding.com",
  pool_size: 10

config :helen, Switch.Command,
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
