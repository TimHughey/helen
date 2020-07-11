# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :helen, ecto_repos: [Repo]

config :scribe, style: Scribe.Style.GithubMarkdown

# default settings for dev and test, must override in prod
config :helen,
  feeds: [
    prefix: "dev",
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
