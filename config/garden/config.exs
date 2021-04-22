# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :garden, :suninfo_wait_ms, 1000

config :garden, Lights,
  cfg_file: "rel/toml/garden/lighting.toml",
  suninfo_wait_ms: 1000
