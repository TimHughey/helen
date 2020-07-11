defmodule Jobs.Seedlings do
  @moduledoc false

  def lights(:day),
    do: Switch.position("germination lights", position: true, ensure: true)

  def lights(:night),
    do: Switch.position("germination lights", position: false, ensure: true)
end
