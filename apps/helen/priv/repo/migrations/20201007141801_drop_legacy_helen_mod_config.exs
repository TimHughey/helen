defmodule Repo.Migrations.DropLegacyHelenModConfig do
  @moduledoc false

  use Ecto.Migration

  def change do
    drop_if_exists(table("helen_mod_config"))
  end
end
