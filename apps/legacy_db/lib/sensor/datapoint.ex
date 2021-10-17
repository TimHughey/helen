defmodule LegacyDb.Sensor.DataPoint do
  @moduledoc """
  Database functionality for Sensor DataPoint
  """

  use Ecto.Schema

  alias LegacyDb.Sensor.Device

  schema "sensor_datapoint" do
    field(:temp_f, :float)
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:capacitance, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:device, Device)
  end
end
