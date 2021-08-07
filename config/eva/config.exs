import Config

if Config.config_env() == :test do
  config :eva, Eva.Habitat, env_vars: [cfg_path: "EVA_CONFIG_PATH", cfg_file: "EVA_CONFIG_FILE"]

  config :eva, Eva.RefImpl.AutoOff,
    env_vars: [cfg_path: "EVA_CONFIG_PATH", cfg_file: "EVA_AUTOFF_CONFIG_FILE"]
end
