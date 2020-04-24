# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# Configures Elixir's Logger
config :logger,
  console: [metadata: [:module], format: "$time $metadata$message\n"],
  backends: [:console],
  level: :info,
  compile_time_purge_matching: [
    [application: :helen, level_lower_than: :info],
    [application: :swarm, level_lower_than: :error]
  ]

config :scribe, style: Scribe.Style.GithubMarkdown

# General application configuration
config :helen,
  ecto_repos: [Repo],
  build_env: "#{Mix.env()}",
  namespace: Web,
  generators: [context_app: false],
  # default settings for dev and test, must override in prod
  feeds: [
    cmd: {"dev/ruth/f/command", 1},
    rpt: {"dev/+/f/report", 0}
  ],
  # Supervision Tree and Initial Opts (listed in startup order)
  sup_tree: [
    {Repo, []},
    {Janitor.Supervisor, []},
    :core_supervisors,
    # TODO: once the Supervisors below are implemented remove the following
    #       specific list of supervisors
    :protocol_supervisors,
    :support_workers,
    :worker_supervisors,
    :misc_workers,
    :helen
  ],
  core_supervisors: [
    # TODO: implement the Supervisors below to create a 'proper'
    #       supervisom tree that does not restart servers uncessary
    # {Protocols.Supervisor, []},
    # {Support.Supervisor, []},
    # {Workers.Supervisor, []},
    # {Misc.Supervisors, []}
  ],
  protocol_supervisors: [
    {Fact.Supervisor, [log: [init: false, init_args: false]]},
    {Mqtt.Supervisor, []}
  ],
  support_workers: [],
  worker_supervisors: [
    # DynamicSupervisors
    {Dutycycle.Supervisor, [start_workers: true]},
    {Thermostat.Supervisor, [start_workers: true]}
  ],
  misc_workers: [
    {Helen.Scheduler, []}
  ],
  helen: [
    {Helen.Supervisor, []}
  ]

config :helen, Helen.Application, log: [init: false]

config :helen, Helen.Scheduler,
  global: true,
  run_strategy: Quantum.RunStrategy.Local,
  timezone: "America/New_York"

config :helen, Janitor,
  log: [init: true, init_args: false],
  metrics_frequency: [orphan: [minutes: 5], switch_cmd: [minutes: 5]]

config :helen, Janitor.Supervisor, log: [init: true, init_args: false]

config :helen, MessageSave,
  log: [init: false],
  save: false,
  save_opts: [],
  forward: false,
  forward_opts: [in: [feed: {"dev/mcr/f/report", 0}]],
  purge: [all_at_startup: true, older_than: [minutes: 20], log: false]

config :helen, Mqtt.Inbound,
  additional_message_flags: [
    log_invalid_readings: true,
    log_roundtrip_times: true
  ],
  periodic_log: [
    enable: false,
    first: {:mins, 5},
    repeat: {:hrs, 60}
  ],
  log_reading: false,
  temperature_msgs: {Sensor, :external_update},
  remote_msgs: {Remote, :external_update},
  pwm_msgs: {PulseWidth, :external_update}

config :helen, OTA,
  url: [
    host: "www.wisslanding.com",
    uri: "helen/firmware",
    fw_file: "latest.bin"
  ]

config :helen, Repo,
  migration_timestamps: [type: :utc_datetime_usec],
  adapter: Ecto.Adapters.Postgres

config :helen, Switch.Device, log: [cmd_ack: false]

import_config "#{Mix.env()}.exs"
