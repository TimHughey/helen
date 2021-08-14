import Config

if Config.config_env() in [:dev, :test] do
  config :eva, Eva.RefImpl.AutoOff, cfg_file: "apps/eva/test/reference_impl/toml/autooff.toml"
  config :eva, Eva.RefImpl.RuthLED, cfg_file: "apps/eva/test/reference_impl/toml/ruth_led.toml"
end
