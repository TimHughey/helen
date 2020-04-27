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

import_config "#{Mix.env()}.exs"
