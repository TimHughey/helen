defmodule Repo.Migrations.AddLightDeskToRemoteProfile do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter(table("remote_profile")) do
      add(:lightdesk_enable, :boolean, default: false)
    end
  end
end
