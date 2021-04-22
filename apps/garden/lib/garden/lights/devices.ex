defmodule Lights.Devices do
  @moduledoc false

  use Lights.Devices.Impl

  def default_node, do: :"prod@helen.live.wisslanding.com"
end
