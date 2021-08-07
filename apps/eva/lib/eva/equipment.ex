defmodule Eva.Equipment do
  require Logger

  alias __MODULE__
  alias Alfred.ExecResult
  alias Broom.TrackerEntry

  defstruct name: nil, impact: nil, status: %Alfred.MutableStatus{}, cmd: :none

  @type t :: %Equipment{
          name: String.t(),
          impact: :raises | :lowers,
          status: Alfred.MutableStatus.t(),
          cmd: Alfred.ExecResult.t()
        }

  def handle_release(%TrackerEntry{} = _te, %Equipment{} = equip) do
    %Equipment{equip | cmd: :released}
  end

  def new(x) do
    equipment = x[:equipment]
    name = equipment[:name] || "unset"
    impact = equipment[:impact] || "unset"

    %Equipment{name: name, impact: impact |> String.to_atom()}
  end

  def off(%Equipment{} = equip, opts \\ []) do
    opts = [notify_when_released: true] ++ opts
    Alfred.off(equip.name, opts) |> record_cmd_result(equip)
  end

  def on(%Equipment{} = equip, opts \\ []) do
    opts = [notify_when_released: true] ++ opts
    Alfred.on(equip.name, opts) |> record_cmd_result(equip)
  end

  def update_status(%Equipment{} = x) do
    %Equipment{x | status: Alfred.status(x.name)}
  end

  # (1 of x) when the command is pending save it
  defp record_cmd_result(%ExecResult{rc: :pending} = er, %Equipment{} = equip) do
    %Equipment{equip | cmd: er}
  end

  # (2 of x) the equipment is already set as required
  defp record_cmd_result(%ExecResult{rc: :ok}, %Equipment{} = equip) do
    %Equipment{equip | cmd: :ok}
  end

  defp record_cmd_result(%ExecResult{} = er, %Equipment{} = equip) do
    Logger.info("\n#{inspect(er, pretty: true)}")

    equip
  end
end
