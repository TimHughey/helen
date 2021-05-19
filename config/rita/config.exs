import Config

config :rita, ecto_repos: [Rita]

import_config "#{config_env()}.exs"
