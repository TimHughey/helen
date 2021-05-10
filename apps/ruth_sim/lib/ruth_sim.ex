defmodule RuthSim do
  require Logger

  def default_device(%{type: type} = ctx) do
    put_default = fn x -> put_in(ctx, [:default_device], x) end

    case type do
      "pwm" -> PwmSim.default_device() |> put_default.()
      "switch" -> SwitchSim.default_device() |> put_default.()
    end
  end

  def freshen(ctx) do
    case ctx do
      %{type: "pwm"} -> PwmSim.freshen(ctx)
      %{type: "switch"} -> SwitchSim.freshen(ctx)
    end
  end

  def make_device(ctx) do
    ctx
    |> RuthSim.Mqtt.add_roundtrip_ref()
    |> PwmSim.make_device()
    |> SwitchSim.make_device()
  end
end
