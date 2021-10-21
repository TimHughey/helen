import Config

config :betty, Betty.Connection, database: "helen_prod"

import_config "#{config_env()}-secret.exs"
