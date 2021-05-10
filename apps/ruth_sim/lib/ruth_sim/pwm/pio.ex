defmodule PwmSim.Pio do
  alias PwmSim.Pio

  defstruct pio: 0, cmd: "off", type: "builtin", args: %{}

  @type t :: %__MODULE__{pio: 0..3, cmd: binary}

  # (1 of 2) execute map matches pio
  def execute(%Pio{pio: dev_pio} = x, %{pio: exec_pio} = exec_map) when dev_pio == exec_pio do
    update_pio(x, exec_map)
  end

  # (2 of 2) execute map does not match State, do nothing
  def execute(%Pio{} = x, _exec_map), do: x

  # (1 of 2) execute cmd is on or off
  def update_pio(%Pio{}, %{cmd: c}) when c in ["off", "on"] do
    %Pio{cmd: c}
  end

  # (2 of 2) execute cmd is custom and has type, take entire cmd map
  def update_pio(%Pio{}, %{cmd: c, type: t} = cm) when is_binary(c) and is_binary(t) do
    %Pio{cmd: c, type: t, args: Map.drop(cm, [:cmd, :type])}
  end
end
