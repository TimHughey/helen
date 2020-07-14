defmodule Switch.Notify do
  @moduledoc """
    Switch GenNotify Implementation
  """

  use GenNotify

  alias Switch.DB.Device, as: Device

  ##
  ## Required callback implementations
  ##

  @impl true
  def extract_dev_alias_from_msg(%{device: dev_tuple}) do
    case dev_tuple do
      {:ok, %Device{aliases: x}} when x == [] -> nil
      {:ok, %Device{aliases: x}} when is_list(x) -> hd(x)
      _no_match -> nil
    end
  end

  @impl true
  def extract_dev_alias_from_msg(_no_match), do: nil
end
