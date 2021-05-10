defmodule SwitchSim.Pio do
  alias SwitchSim.Pio

  defstruct pio: 0, cmd: "off", args: %{}

  @type t :: %__MODULE__{pio: 0..12, cmd: binary}

  # (1 of 2) execute map matches pio
  def execute(%Pio{pio: dev_pio} = x, %{pio: exec_pio} = exec_map) when dev_pio == exec_pio do
    update_pio(x, exec_map)
  end

  # (2 of 2) execute map does not match State, do nothing
  def execute(%Pio{} = x, _exec_map), do: x

  # execute cmd is on or off
  def update_pio(%Pio{}, %{cmd: c}) when c in ["off", "on"] do
    %Pio{cmd: c}
  end
end
