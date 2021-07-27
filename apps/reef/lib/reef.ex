defmodule NewReef do
  require Logger
  alias NewReef.Config

  def parse_config do
    base_path = System.get_env("REEF_CONFIG_PATH") || "."
    cfg_file = System.get_env("REEF_CONFIG_FILE") || "defaults_v2.txt"

    config = Config.parse(base_path, cfg_file)

    Logger.info("\n#{inspect(config, pretty: true)}")
  end
end
