# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger,
  # level: :debug
  # level: :warn
  level: :info

config :helen,
  # overrides from config.exs
  protocol_supervisors: [
    {Fact.Supervisor, [log: [init: false]]}
  ],
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
# import_config "modules/msg_save_forward.exs"

config :helen, Fact.Influx,
  database: "helen_dev",
  host: "jophiel.wisslanding.com",
  auth: [method: :basic, username: "helen_test", password: "helen_test"],
  http_opts: [insecure: true],
  pool: [max_overflow: 10, size: 5, timeout: 150_000, max_connections: 10],
  port: 8086,
  scheme: "http",
  writer: Instream.Writer.Line

config :helen, Janitor.Supervisor, log: [init: true, init_args: false]

config :helen, Janitor,
  log: [init: true, init_args: true],
  metrics_frequency: [orphan: [minutes: 5], switch_cmd: [minutes: 5]]

config :helen, Mqtt.Client,
  log_dropped_msgs: true,
  tort_opts: [
    client_id: "helen-#{Mix.env()}",
    user_name: "mqtt",
    password: "mqtt",
    server:
      {Tortoise.Transport.Tcp, host: "jophiel.wisslanding.com", port: 1883},
    keep_alive: 15
  ],
  timesync: [frequency: {:mins, 1}, loops: 5, forever: true, log: false],
  log: [init: false]

config :helen, Mqtt.Inbound,
  additional_message_flags: [
    switch_redesign: true
  ]

config :helen, OTA, [
  {:url,
   [
     host: "www.wisslanding.com",
     uri: "helen/firmware",
     fw_file: "latest.bin"
   ]}
]

config :helen, PulseWidthCmd,
  orphan: [
    at_startup: true,
    sent_before: [seconds: 10],
    log: true
  ],
  purge: [
    at_startup: true,
    interval: [minutes: 2],
    older_than: [days: 30],
    log: false
  ]

config :helen, Repo,
  database: "helen_dev",
  username: "helen_dev",
  password: "helen_dev",
  port: 15432,
  hostname: "db.dev.wisslanding.com",
  pool_size: 10,
  migration_timestamps: [type: :utc_datetime_usec],
  adapter: Ecto.Adapters.Postgres

config :helen, Switch.Command,
  # NOTE:  older_than lists are passed to Timex to create a
  #        shifted DateTime in UTC
  orphan: [
    at_startup: true,
    sent_before: [seconds: 10],
    log: false
  ],
  purge: [
    at_startup: true,
    interval: [minutes: 2],
    older_than: [days: 30],
    log: true
  ]

config :helen, Helen.Scheduler,
  jobs: [
    # Every minute
    {:touch,
     [
       schedule: {:cron, "* * * * *"},
       task: {Jobs, :touch_file, ["/tmp/helen-dev.touch"]},
       run_strategy: Quantum.RunStrategy.Local
     ]},
    {:purge_readings,
     [
       schedule: {:cron, "22,56 * * * *"},
       task: {Jobs, :purge_readings, [[days: -30]]},
       run_strategy: Quantum.RunStrategy.Local
     ]}
  ]
