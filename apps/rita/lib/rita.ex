defmodule Rita do
  use Ecto.Repo,
    otp_app: :rita,
    adapter: Ecto.Adapters.Postgres
end
