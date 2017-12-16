defmodule Mcp.SensorRelHum do
@moduledoc """
  The SensorTemperature module provides individual temperature readings for
  a Sensor
"""

require Logger
use Timex
use Timex.Ecto.Timestamps
use Ecto.Schema

schema "sensor_relhum" do
  field :rh, :float
  field :ttl_ms, :integer
  belongs_to :sensor, Mcp.Switch

  timestamps usec: true
end

end
