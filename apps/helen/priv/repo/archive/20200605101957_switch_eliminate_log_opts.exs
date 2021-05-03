defmodule Repo.Migrations.SwitchEliminateLogOpts do
  use Ecto.Migration

  def change do
    alter table("switch_alias") do
      remove(:log_opts)
    end

    alter table("switch_device") do
      remove(:log_opts)
    end

    alter table("switch_command") do
      remove(:log_opts)
    end
  end
end
