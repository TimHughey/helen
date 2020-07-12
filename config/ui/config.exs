# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Configures the endpoint
config :ui, UI.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "uHqvJEz8vTo0YlOH4BzlpuJLPvWCjdpbXjdURYPIGlthgj3S79BQU6vzyEhZcBt2",
  render_errors: [view: UI.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: UI.PubSub,
  live_view: [signing_salt: "gcVuZPJL"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
