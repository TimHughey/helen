defmodule Broom.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :broom,
    adapter: Ecto.Adapters.Postgres
end
