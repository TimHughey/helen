defmodule Helen.Worker.Config.DB.Line do
  @moduledoc false

  use Ecto.Schema

  alias Helen.Worker.Config.DB

  schema "worker_config_line" do
    field(:line, :string)

    belongs_to(:config, DB.Config)
  end
end
