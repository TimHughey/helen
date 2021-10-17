defmodule LegacyDb.Repo do
  use Ecto.Repo,
    otp_app: :legacy_db,
    adapter: Ecto.Adapters.Postgres
end
