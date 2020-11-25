defmodule Repo.Migrations.MatchRemoteProfileToActualTasks do
  @moduledoc false

  use Ecto.Migration

  def change do
    alter(table("remote_profile")) do
      remove(:dalsemi_discover_stack, :integer)
      remove(:dalsemi_discover_priority, :integer)
      remove(:dalsemi_discover_interval_ms, :integer)
      remove(:dalsemi_convert_stack, :integer)
      remove(:dalsemi_convert_priority, :integer)
      remove(:dalsemi_convert_interval_ms, :integer)

      remove(:i2c_discover_stack, :integer)
      remove(:i2c_discover_priority, :integer)
      remove(:i2c_discover_interval_ms, :integer)

      remove(:pwm_command_stack, :integer)
      remove(:pwm_command_priority, :integer)
      remove(:pwm_core_interval_ms, :integer)
    end
  end
end
