defmodule Reef.Captain do
  @moduledoc """
  Reef Captain
  """

  use Helen.Worker.Config

  @doc false
  def subworker_mod(subworker) do
    case subworker do
      "pump" -> Reef.MixTank.Pump
      "air" -> Reef.MixTank.Air
      "rodi" -> Reef.MixTank.Rodi
      "mix_heater" -> Reef.MixTank.Temp
    end
  end

  def subworker_toggle(subworker) do
    mod = subworker_mod(subworker)

    apply(mod, :toggle, [])
  end
end
