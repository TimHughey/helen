# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :garden, :suninfo_wait_ms, 1000

if config_env() in [:dev, :test] do
  config :garden,
    cfg_path: "apps/garden/test/toml",
    cfg_file: "config.toml"
else
  config :garden,
    cfg_path: "rel/toml/garden",
    cfg_file: "config.toml"
end
