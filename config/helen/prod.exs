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
    server: {Tortoise.Transport.Tcp, host: "** set in prod.secret.exs", port: 1883},
    keep_alive: 15
  ]

config :helen, Mqtt.Inbound,
  log: [
    engine_metrics: false
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
    sent_before: "PT12S",
    older_than: "PT1M"
  ],
  purge: [
    at_startup: true,
    interval: "PT2M",
    older_than: "PT30D"
  ],
  metrics: "PT5S"

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
    at_startup: true,
    sent_before: "PT12S"
  ],
  purge: [
    at_startup: true,
    interval: "PT2M",
    older_than: "PT30D"
  ],
  metrics: "PT5S"

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
     ]}
  ]

secret =
  [System.get_env("HOME"), "devel", "shell", "local", "helen-home", "helen_app"]
  |> Path.join()

import_config Path.join([secret, "prod.secret.exs"])
