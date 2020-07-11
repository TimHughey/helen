defmodule Repo.Migrations.AddRemoteProfileDescription do
  use Ecto.Migration

  def change do
    alter table("remote_profile") do
      add(:description, :string, default: " ")
    end


  end
end
