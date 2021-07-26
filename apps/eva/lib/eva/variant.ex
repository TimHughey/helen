defprotocol Eva.Variant do
  @type server_mode() :: :starting | :ready | :standby
  @type instruct() :: struct()
  @type variant() :: struct()
  @spec control(variant(), Alfred.NotifyMemo.t(), server_mode()) :: variant()
  def control(variant, memo, mode)

  @spec execute(struct(), Alfred.ExecCmd.t(), GenServer.from()) :: Alfred.ExecResult.t()
  def execute(variant, exec_cmd, from)

  @spec handle_instruct(variant(), instruct()) :: variant()
  def handle_instruct(variant, instruct)

  @spec handle_notify(struct(), Alfred.NotifyMemo.t(), server_mode()) :: struct()
  def handle_notify(variant, memo, mode)

  @spec handle_release(struct(), Broom.TrackerEntry.t()) :: struct()
  def handle_release(variant, tracker_entry)
end

defmodule Eva.Variant.Factory do
  alias Eva.{Follow, Opts, Setpoint, TimedCmd}

  def new(toml_rc, %Opts{} = opts) do
    case toml_rc do
      {:ok, %{variant: "setpoint"} = x} -> Setpoint.new(opts, cfg: x)
      {:ok, %{variant: "follow"} = x} -> Follow.new(opts, cfg: x)
      {:ok, %{variant: "timed_cmd"} = x} -> TimedCmd.new(opts, cfg: x)
      {:error, error} -> {:error, error}
    end
  end
end
