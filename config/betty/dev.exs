# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :betty, Betty.Connecton,
  database: "helen_dev",
  host: "influx.dev.wisslanding.com",
  auth: [method: :basic, username: "helen_dev", password: "helen_dev"]
