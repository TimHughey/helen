# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :helen, ecto_repos: [Repo]

config :helen, OTA, [
  {:uri,
   [
     host: "www.wisslanding.com",
     path: "helen/firmware",
     file: "latest.bin"
   ]}
]

import_config "#{Mix.env()}.exs"
