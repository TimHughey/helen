# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# useful functions
# must be set to variables since this is not a module
seconds = fn x -> x * 1000 end
minutes = fn x -> seconds.(60 * x) end

config :logger,
  # level: :debug
  # level: :warn
  level: :info

config :mcp,
  feeds: [
    cmd: {"prod/mcr/f/command", :qos0},
    rpt: {"prod/mcr/f/report", :qos0},
    ota: {"prod/mcr/f/ota", :qos0}
  ]

config :mcp, Dutycycle, routine_check_ms: 1000

config :mcp, Janitor,
  switch_cmds: [
    purge: true,
    interval: {:mins, 1},
    older_than: {:months, 3},
    log: false
  ],
  orphan_acks: [interval: {:secs, 30}, older_than: {:mins, 1}, log: true]

config :mcp, MessageSave,
  save: false,
  delete: [all_at_startup: true, older_than_hrs: 7 * 24]

config :mcp, Mqtt.Client,
  log_dropped_msgs: true,
  broker: [
    # must be a char string (not binary) for emqttc
    host: '** set in prod.secret.exs **',
    port: 1883,
    client_id: "janice-prod",
    clean_sess: false,
    username: "** set in prod.secret.exs",
    password: "** set in prod.secret.exs",
    auto_resub: true,
    keepalive: 15 * 60,
    reconnect: 2
  ],
  timesync: [frequency: 60 * 60 * 1000, loops: 0, forever: true, log: false]

config :mcp, Mqtt.InboundMessage,
  periodic_log: [
    enable: false,
    first_ms: 5 * 60 * 1000,
    repeat_ms: 60 * 60 * 1000
  ]

config :mcp, Fact.Influx,
  database: "merc_repo",
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
  writer: Instream.Writer.Line,
  periodic_log_first_ms: 1 * 60 * 1000,
  periodic_log_ms: 15 * 60 * 1000

config :mcp, Mixtank.Control, control_temp_secs: 27

config :mcp, Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "jan_prod",
  username: "jan_prod",
  password: "** set in prod.secret.exs",
  hostname: "** set in prod.secret.exs",
  pool_size: 20

config :mcp, Janice.Scheduler,
  global: true,
  jobs: [
    # Every minute
    {:touch,
     [
       schedule: {:cron, "* * * * *"},
       task: {Janice.Jobs, :touch_file, ["/tmp/janice-standby-every-minute"]},
       run_strategy: Quantum.RunStrategy.Local
     ]}
    # {:germination_on,
    #  [
    #    schedule: {:cron, "*/2 8-21 * * *"},
    #    task: {Janice.Jobs, :switch_control, ["germination_light", true]},
    #    run_strategy: Quantum.RunStrategy.Local
    #  ]},
    # {:germination_off,
    #  [
    #    schedule: {:cron, "*/2 22-7 * * *"},
    #    task: {Janice.Jobs, :switch_control, ["germination_light", false]},
    #    run_strategy: Quantum.RunStrategy.Local
    #  ]},
    # {:germination_heat,
    #  [
    #    schedule: {:cron, "*/2 * * * *"},
    #    task: {Janice.Jobs, :switch_control, ["germination_heat", true]},
    #    run_strategy: Quantum.RunStrategy.Local
    #  ]}
    # control germination light and heat
    # {"*/2 8-19 * * *", {Janice.Jobs, :switch_control, ["germination_light", true]}},
    # {"*/2 20-7 * * *", {Janice.Jobs, :switch_control, ["germination_light", false]}},
    # {"*/2 * * * *", {Janice.Jobs, :switch_control, ["germination_heat", true]}}
    # {"*/2 21-7 * * *", {Janice.Jobs, :flush, []}},
    # {"*/2 8-20 * * *", {Janice.Jobs, :grow, []}}
    # SUN = 0, MON = 1, TUE = 2, WED = 3, THU = 4, FRI = 5, SAT = 6
    # {"0 18 * * 4", {Janice.Jobs, :reefwater, [:fill_overnight]}},
    # {"0 7 * * 5", {Janice.Jobs, :reefwater, [:fill_daytime]}},
    # {"0 18 * * 5", {Janice.Jobs, :reefwater, [:mix]}},
    # {"0 20 * * 0", {Janice.Jobs, :reefwater, [:eco]}}

    # Every 15 minutes
    # {"*/15 * * * *",   fn -> System.cmd("rm", ["/tmp/tmp_"]) end},
    # Runs on 18, 20, 22, 0, 2, 4, 6:
    # {"0 18-6/2 * * *", fn -> :mnesia.backup('/var/backup/mnesia') end},
    # Runs every midnight:
    # {"@daily",         {Backup, :backup, []}}
  ]

config :mcp, Mcp.SoakTest,
  # don't start
  startup_delay_ms: 0,
  periodic_log_first_ms: 30 * 60 * 1000,
  periodic_log_ms: 60 * 60 * 1000,
  flash_led_ms: 3 * 1000

config :mcp, Switch, logCmdAck: false

import_config "prod.secret.exs"
