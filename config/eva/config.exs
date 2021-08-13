import Config

if Config.config_env() == :test do
  config :eva, Eva.Habitat, cfg_file: "apps/eva/test/reference_impl/toml/timed_cmd.toml"
  config :eva, Eva.RefImpl.AutoOff, cfg_file: "apps/eva/test/reference_impl/toml/autooff.toml"
  config :eva, Eva.RefImpl.RuthLED, cfg_file: "apps/eva/test/reference_impl/toml/ruth_led.toml"
end
