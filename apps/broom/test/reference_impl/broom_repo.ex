defmodule BroomRepo do
  use Ecto.Repo,
    otp_app: :broom,
    adapter: Ecto.Adapters.Postgres
end
