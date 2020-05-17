# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :helen, ecto_repos: [Repo]

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

# default settings for dev and test, must override in prod
config :helen,
  feeds: [
    prefix: "dev",
    cmd: {"dev/ruth/f/command", 1},
    rpt: {"prod/r/#", 0}
  ]

config :helen, OTA, [
  {:uri,
   [
     host: "www.wisslanding.com",
     path: "helen/firmware",
     file: "latest.bin"
   ]}
]

import_config "#{Mix.env()}.exs"
