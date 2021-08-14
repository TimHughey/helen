# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :garden, :suninfo_wait_ms, 1000

if config_env() in [:dev, :test] do
  config :garden, cfg_path: "apps/garden/test/toml", cfg_file: "config.toml"

  config :garden, Garden.Equipment.Irrigation.Power, cfg_file: "irrigation_power.toml"
  config :garden, Garden.Equipment.Irrigation.Garden, cfg_file: "irrigation_garden.toml"
  config :garden, Garden.Equipment.Irrigation.Porch, cfg_file: "irrigation_porch.toml"
  config :garden, Garden.Equipment.Lighting.Evergreen, cfg_file: "lighting_evergreen.toml"
  config :garden, Garden.Equipment.Lighting.RedMaple, cfg_file: "lighting_redmaple.toml"
  config :garden, Garden.Equipment.Lighting.Chandelier, cfg_file: "lighting_chandelier.toml"
else
  config :garden,
    cfg_path: "rel/toml/garden",
    cfg_file: "config.toml"
end
