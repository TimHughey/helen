# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger,
  # level: :debug
  # level: :warn
  level: :info

config :helen,
  feeds: [
    prefix: "prod",
    rpt: {"prod/r/#", 0}
  ]

config :helen, Mqtt.Client,
  log_dropped_msgs: true,
  tort_opts: [
    client_id: "helen-prod",
    user_name: "** set in prod.secret.exs",
    password: "** set in prod.secret.exs",
    server:
      {Tortoise.Transport.Tcp, host: "** set in prod.secret.exs", port: 1883},
    keep_alive: 15
  ],
  # timesync also keeps the MQTT client connection alive
  # the MQTT spec requires both sending and receiving to prevent disconnects
  timesync: [frequency: {:mins, 2}, loops: 0, forever: true, log: false]

config :helen, Mqtt.Inbound,
  additional_message_flags: [
    log_invalid_readings: true,
    log_roundtrip_times: true
  ],
  periodic_log: [
    enable: false,
    first: {:mins, 5},
    repeat: {:hrs, 60}
  ]

config :helen, Fact.Influx,
  database: "helen_prod",
  host: "** set in prod.secret.exs",
  auth: [
    method: :basic,
    username: "** set in prod.secret.exs",
    password: "** set in prod.secret.exs"
  ],
  http_opts: [insecure: true],
  pool: [max_overflow: 15, size: 10, timeout: 150_000, max_connections: 25],
  port: 8086,
  scheme: "http",
  writer: Instream.Writer.Line

config :helen, PulseWidth.DB.Command,
  orphan: [
    startup_check: true,
    sent_before: [seconds: 1],
    older_than: [minutes: 1]
  ],
  purge: [
    at_startup: true,
    interval: [minutes: 2],
    older_than: [days: 30]
  ],
  metrics: [minutes: 5]

config :helen, Repo,
  database: "helen_prod",
  username: "helen_prod",
  password: "** set in prod.secret.exs",
  hostname: "** set in prod.secret.exs",
  pool_size: 20

config :helen, Switch.DB.Command,
  # NOTE:  older_than lists are passed to Timex to create a
  #        shifted DateTime in UTC
  orphan: [
    startup_check: true,
    sent_before: [seconds: 12],
    older_than: [minutes: 1]
  ],
  purge: [
    at_startup: true,
    interval: [minutes: 2],
    older_than: [days: 30]
  ],
  metrics: [minutes: 5]

config :helen, Thermostat.Supervisor, initial_args: [start_workers: true]

run_strategy = {Quantum.RunStrategy.All, [:"prod@helen.live.wisslanding.com"]}

config :helen, Helen.Scheduler,
  global: true,
  timezone: "America/New_York",
  jobs: [
    # Every minute
    {:touch,
     [
       schedule: {:cron, "* * * * *"},
       task: {Jobs, :touch_file, ["/tmp/helen-prod.touch"]},
       run_strategy: run_strategy
     ]},
    {:seedlings_day,
     [
       schedule: {:cron, "* 06-20 * * *"},
       task: {Jobs.Seedlings, :lights, [:day]},
       run_strategy: run_strategy
     ]},
    {:seedlings_night,
     [
       schedule: {:cron, "* 00-05,21-23 * * *"},
       task: {Jobs.Seedlings, :lights, [:night]},
       run_strategy: run_strategy
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

config :helen, Thermostat.Server, initial_args: [start_workers: true]

import_config "prod.secret.exs"
