import Config

if Config.config_env() == :test do
  config :eva, Eva.Habitat, cfg_path: "apps/eva/test/reference_impl/toml", cfg_file: "timed_cmd.toml"

  config :eva, Eva.RefImpl.AutoOff, cfg_path: "apps/eva/test/reference_impl/toml", cfg_file: "autooff.toml"
end
