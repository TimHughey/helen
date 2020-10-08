defmodule Helen.Worker.Config.DB.Config do
  @moduledoc false

  use Ecto.Schema

  alias Helen.Worker.Config.DB

  schema "worker_config" do
    field(:module, :string)
    field(:comment, :string)
    field(:version, :string)

    has_many(:lines, DB.Line)

    timestamps(type: :utc_datetime_usec)
  end
end
