import Config

config :legacy_db, ecto_repos: [LegacyDb.Repo]

import_config "prod-secret.exs"
