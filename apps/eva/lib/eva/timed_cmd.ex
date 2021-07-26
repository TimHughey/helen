defmodule Eva.TimedCmd.Instruct do
  require Logger

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Broom.TrackerEntry
  alias Eva.Ledger

  defstruct name: "default",
            from: nil,
            cmd: "off",
            for_ms: 0,
            nowait: false,
            then_cmd: nil,
            ref: nil,
            timer: nil,
            expired?: false,
            exec_result: nil,
            ledger: %Ledger{}

  @type t :: %Instruct{
          name: String.t(),
          from: GenServer.from(),
          cmd: String.t(),
          nowait: boolean(),
          for_ms: pos_integer(),
          then_cmd: String.t() | nil,
          ref: reference(),
          timer: reference() | nil,
          expired?: boolean(),
          exec_result: ExecResult.t() | nil | :released,
          ledger: Ledger.t()
        }

  def completed(%Instruct{ledger: ledger} = instruct) do
    %Instruct{instruct | ledger: Ledger.completed(ledger)}
  end

  def execute(%Instruct{} = x) do
    result = %ExecCmd{name: x.name, cmd: x.cmd, cmd_opts: [notify_when_released: true]} |> Alfred.execute()

    Logger.debug("\n#{inspect(result, pretty: true)}")

    instruct = %Instruct{x | exec_result: result, ledger: Ledger.executed(x.ledger)}

    case result do
      # the command is pending, wait for the release before starting for_ms timer (if specified)
      %ExecResult{rc: :ok, refid: x} when is_binary(x) -> instruct
      # equipment matches desired cmd, start for_ms timer immediately
      %ExecResult{rc: :ok} -> instruct |> schedule_timer()
      # TODO an error has occurred
      _ -> instruct
    end
  end

  # (1 of x) quietly ignore expired timers for out of date instructions
  def expired(%Instruct{ref: ref} = instruct, %Instruct{ref: expired_ref})
      when ref != expired_ref do
    instruct
  end

  def expired(%Instruct{} = x, _expired_refid) do
    Logger.debug("\n#{inspect(x, pretty: true)}")

    case %Instruct{x | expired?: true} do
      # if then_cmd is requested create and execute a new Instruct
      %Instruct{then_cmd: cmd} = x when is_binary(cmd) ->
        %Instruct{
          name: x.name,
          cmd: cmd,
          for_ms: 0,
          nowait: true,
          from: x.from,
          ref: x.ref,
          ledger: Ledger.new(x.ledger)
        }
        |> execute()

      %Instruct{} = x ->
        %Instruct{x | ledger: Ledger.expired(x.ledger)} |> send_complete() |> completed()
    end
  end

  def new(equipment_name, %ExecCmd{} = ec, {pid, _tag} = _from) do
    default = %Instruct{}

    %Instruct{
      name: equipment_name,
      cmd: ec.cmd,
      from: pid,
      for_ms: ec.cmd_params[:for_ms] || default.for_ms,
      nowait: ec.cmd_params[:nowait] || default.nowait,
      then_cmd: ec.cmd_params[:then_cmd] || default.then_cmd,
      ref: make_ref(),
      ledger: Ledger.new()
    }
  end

  def prime(equipment_name) do
    %Instruct{name: equipment_name, cmd: "off", ref: make_ref(), ledger: Ledger.new()}
  end

  def released(%Instruct{exec_result: %ExecResult{refid: refid}} = instruct, %TrackerEntry{
        refid: tracked_refid
      })
      when refid == tracked_refid do
    %Instruct{instruct | exec_result: :released, ledger: Ledger.released(instruct.ledger)}
    |> schedule_timer()
    |> tap(fn x -> Logger.debug("\n#{inspect(x, pretty: true)}") end)
  end

  defp send_complete(%Instruct{nowait: false, from: from} = instruct) when is_pid(from) do
    from |> Process.send({Eva, :complete, instruct.ref}, [])

    %Instruct{instruct | ledger: Ledger.notified(instruct.ledger)}
  end

  defp send_complete(%Instruct{} = instruct), do: instruct

  defp schedule_timer(%Instruct{for_ms: for_ms} = x) when is_integer(for_ms) do
    %Instruct{x | timer: Process.send_after(self(), {:instruct, x}, x.for_ms)}
  end
end

defmodule Eva.TimedCmd do
  require Logger

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.NotifyMemo, as: Memo
  alias Alfred.NotifyTo
  alias Broom.TrackerEntry
  alias Eva.{Equipment, Names, Opts}
  alias Eva.TimedCmd.Instruct

  defstruct name: nil,
            mod: nil,
            equipment: %Equipment{},
            names: %{needed: [], found: []},
            notifies: %{},
            instruct: nil,
            mode: :init,
            valid?: true

  @type mode() :: :init | :timed_cmd | :idle | :standby
  @type t :: %TimedCmd{
          name: String.t(),
          mod: module(),
          equipment: Equipment.t(),
          names: %{needed: list(), found: list()},
          notifies: %{required(reference()) => NotifyTo.t()},
          instruct: Instruct.t() | nil,
          mode: mode(),
          valid?: boolean()
        }

  def control(%TimedCmd{instruct: nil} = tc, %Memo{}, _mode) do
    instruct = Instruct.prime(tc.equipment.name) |> Instruct.execute()

    update(tc, instruct)
  end

  def control(%TimedCmd{} = tc, %Memo{}, _mode) do
    tc
  end

  def execute(%TimedCmd{mode: mode} = tc, %ExecCmd{} = ec, from) when mode in [:ready, :standby] do
    instruct = Instruct.new(tc.equipment.name, ec, from) |> Instruct.execute()

    Logger.debug("\n#{inspect(instruct, pretty: true)}")

    result = %ExecResult{
      name: tc.name,
      rc: if(instruct.exec_result.rc == :ok, do: :accepted, else: :error),
      cmd: ec.cmd,
      will_notify_when_released: true,
      refid: instruct.ref,
      instruct: instruct
    }

    {update(tc, instruct), result}
  end

  def handle_instruct(%TimedCmd{} = v, %Instruct{} = instruct) do
    v.instruct |> Instruct.expired(instruct) |> update(v)
  end

  def handle_notify(%TimedCmd{} = v, %Memo{} = _momo, :starting), do: v

  def handle_notify(%TimedCmd{} = v, %Memo{} = memo, _mode) do
    if v.equipment.name == memo.name do
      Equipment.update_status(v.equipment) |> update(v)
    else
      v
    end
  end

  def handle_release(%TimedCmd{} = tc, %TrackerEntry{} = te) do
    tc.instruct |> Instruct.released(te) |> update(tc)
  end

  def mode(%TimedCmd{mode: prev_mode} = v, mode) do
    v = %TimedCmd{v | mode: mode}
    fake_memo = %Memo{name: v.equipment.name}

    case {v, mode} do
      {v, mode} when mode == prev_mode -> v
      {v, :resume} -> v |> control(fake_memo, :ready)
      {v, :standby} -> v |> control(fake_memo, :standby)
      {v, _mode} -> v
    end
  end

  def new(%Opts{} = opts, extra_opts) do
    cfg = extra_opts[:cfg]
    equipment = Equipment.new(cfg)

    %TimedCmd{
      name: cfg[:name],
      mod: opts.server.name,
      equipment: equipment,
      names: Names.new([equipment.name]),
      notifies: %{},
      valid?: true
    }
  end

  # defp change_token(%TimedCmd{} = v), do: %TimedCmd{v | token: make_ref()}

  defp update(%Equipment{} = x, %TimedCmd{} = v), do: %TimedCmd{v | equipment: x}
  defp update(%Instruct{} = x, %TimedCmd{} = v), do: %TimedCmd{v | instruct: x}
  defp update(%TimedCmd{} = v, %Instruct{} = x), do: %TimedCmd{v | instruct: x}
  defp update(:complete, %TimedCmd{} = v), do: %TimedCmd{v | instruct: :complete}
end

defimpl Eva.Variant, for: Eva.TimedCmd do
  alias Alfred.ExecCmd
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.TimedCmd
  alias Eva.TimedCmd.Instruct

  def control(%TimedCmd{} = tc, %Memo{} = memo, mode), do: TimedCmd.control(tc, memo, mode)
  def execute(%TimedCmd{} = tc, %ExecCmd{} = ec, from), do: TimedCmd.execute(tc, ec, from)
  def handle_instruct(%TimedCmd{} = tc, %Instruct{} = x), do: TimedCmd.handle_instruct(tc, x)
  def handle_notify(%TimedCmd{} = tc, %Memo{} = memo, mode), do: TimedCmd.handle_notify(tc, memo, mode)
  def handle_release(%TimedCmd{} = tc, %TrackerEntry{} = te), do: TimedCmd.handle_release(tc, te)
  def mode(%TimedCmd{} = tc, mode), do: TimedCmd.mode(tc, mode)
end
