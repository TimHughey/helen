defmodule Repo.Migrations.PulseWidthRenamedAckAtForConsistency do
  use Ecto.Migration

  def change do
    rename(table(:pwm_cmd), :ack_at, to: :acked_at)
    rename(table(:pwm_cmd), :orphan, to: :orphaned)
  end
end
