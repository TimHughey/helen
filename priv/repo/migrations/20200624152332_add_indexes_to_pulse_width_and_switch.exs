defmodule Repo.Migrations.AddIndexesToPulseWidthAndSwitch do
  use Ecto.Migration

  def change do
    for t <- ["switch_command", "pwm_cmd"] do
      # drop legacy multi-column indexes
      for c <- [[:ack_at, :sent_at], [:acked, :orphan]] do
        drop_if_exists(index(t, [c]))
      end

      # create new single column indexes
      for c <- [:acked, :orphan, :sent_at, :alias_id] do
        create_if_not_exists(index(t, [c]))
      end
    end

    for t <- ["switch_alias", "pwm_alias"] do
      create_if_not_exists(index(t, [:device_id]))
    end
  end
end
