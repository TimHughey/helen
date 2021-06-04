defmodule Sally.Repo do
  use Ecto.Repo,
    otp_app: :sally,
    adapter: Ecto.Adapters.Postgres
end
