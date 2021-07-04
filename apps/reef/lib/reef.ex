defmodule NewReef do
  require Logger
  alias NewReef.Config

  def parse_config(file) do
    base_path = System.get_env("REEF_CONFIGS")

    _config = Config.parse(base_path, file)

    # Logger.info("\n#{inspect(config, pretty: true)}")
  end
end
