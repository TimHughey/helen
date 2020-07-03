defmodule Sensor.Notify do
  @moduledoc """
    Sensor GenNotify Implementation
  """

  use GenNotify

  alias Sensor.DB.{Alias, Device}

  ##
  ## Required callback implementations
  ##

  @impl true
  def extract_dev_alias_from_msg(%{device: dev_tuple}) do
    case dev_tuple do
      {:ok, %Device{_alias_: %Alias{} = x}} -> x
      _no_match -> nil
    end
  end

  @impl true
  def extract_dev_alias_from_msg(_no_match), do: nil
end
