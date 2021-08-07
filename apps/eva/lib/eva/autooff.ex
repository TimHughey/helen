defmodule Eva.AutoOff.Instruct do
  require Logger

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Broom.TrackerEntry
  alias Eva.Ledger

  defstruct name: "default",
            from: nil,
            cmd: "on",
            settle_ms: 10_000,
            ref: nil,
            timer: nil,
            expired?: true,
            exec_result: %ExecResult{},
            ledger: %Ledger{}

  def completed(%Instruct{ledger: ledger} = instruct) do
    # once a command is complete, unlink the processes
    if is_pid(instruct.from), do: Process.unlink(instruct.from)

    %Instruct{instruct | ledger: Ledger.completed(ledger)}
  end

  def execute(%Instruct{} = x) do
    # link the processes while executing a command
    if is_pid(x.from), do: Process.link(x.from)

    result = %ExecCmd{name: x.name, cmd: x.cmd, cmd_opts: [notify_when_released: true]} |> Alfred.execute()

    Logger.debug("\n#{inspect(result, pretty: true)}")

    instruct = %Instruct{x | exec_result: result, ledger: Ledger.executed(x.ledger)}

    case result do
      # the command is pending, wait for the release before starting settle_ms timer
      %ExecResult{rc: :ok, refid: x} when is_binary(x) -> instruct
      # equipment matches desired cmd, start settle_ms timer immediately
      %ExecResult{rc: :ok} -> instruct |> schedule_timer()
      # allow caller to deal with errors by checking exec_result
      _ -> instruct
    end
  end

  def expired(%Instruct{ref: ref} = x, %Instruct{ref: expired_ref}) do
    Logger.debug("\n#{inspect(x, pretty: true)}")

    if ref == expired_ref do
      %Instruct{x | ledger: Ledger.expired(x.ledger)} |> send_complete() |> completed()
    else
      x
    end
  end

  def in_progress?(%Instruct{ledger: ledger}), do: Ledger.in_progress?(ledger)

  def force(equipment_name, cmd) do
    %Instruct{name: equipment_name, cmd: cmd, ref: make_ref(), ledger: Ledger.new()}
  end

  def new(equipment_name, %ExecCmd{} = ec, {pid, _tag} = _from) do
    default = %Instruct{}

    %Instruct{
      name: equipment_name,
      cmd: ec.cmd,
      from: pid,
      settle_ms: ec.cmd_params[:settle_ms] || default.settle_ms,
      ref: make_ref(),
      ledger: Ledger.new()
    }
  end

  def released(%Instruct{} = instruct, %TrackerEntry{}) do
    %Instruct{instruct | ledger: Ledger.released(instruct.ledger)}
    |> schedule_timer()
    |> tap(fn x -> Logger.debug("\n#{inspect(x, pretty: true)}") end)
  end

  defp send_complete(%Instruct{from: from} = instruct) when is_pid(from) do
    from |> Process.send({Eva, :complete, instruct.ref}, [])

    %Instruct{instruct | ledger: Ledger.notified(instruct.ledger)}
  end

  defp send_complete(%Instruct{} = instruct), do: instruct

  defp schedule_timer(%Instruct{settle_ms: settle_ms} = x) when is_integer(settle_ms) do
    %Instruct{x | timer: Process.send_after(self(), {:instruct, x}, settle_ms)}
  end
end

defmodule Eva.AutoOff do
  require Logger
  use Timex

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.AutoOff.Instruct
  alias Eva.{Equipment, Names, Opts}

  defstruct name: nil,
            mod: nil,
            equipment: %Equipment{},
            names: %Names{},
            notifies: %{},
            instruct: :none,
            watch: %{},
            mode: :init,
            settle_for: "PT10S",
            settle_ms: 10_000,
            valid?: true

  def control(%AutoOff{watch: watch, instruct: instruct} = ao, %Memo{}, server_mode) do
    cond do
      # no control until the server is ready
      server_mode != :ready ->
        ao

      # no control until the settle instruction completes
      is_struct(instruct) and Instruct.in_progress?(instruct) ->
        ao

      # no control until we have valid status from watched names
      Enum.any?(watch, fn {_k, v} -> v == "unknown" end) ->
        ao

      # auto off when all watched names are off
      Enum.all?(watch, fn {_k, v} -> v == "off" end) ->
        ao = reset_watch(ao)

        case ao.equipment.status do
          %MutStatus{cmd: "on"} -> %AutoOff{ao | equipment: Equipment.off(ao.equipment), mode: :ready}
          _ -> ao
        end

      # at least one watched name is on, reset all watched names
      true ->
        reset_watch(ao)
    end
  end

  def execute(%AutoOff{mode: :ready} = ao, %ExecCmd{cmd: "on"} = ec, from) do
    instruct = Instruct.new(ao.equipment.name, ec, from) |> Instruct.execute()

    Logger.debug("\n#{inspect(instruct, pretty: true)}")

    result = %ExecResult{
      name: ao.name,
      rc: if(instruct.exec_result.rc == :ok, do: :accepted, else: :error),
      cmd: ec.cmd,
      will_notify_when_released: if(instruct.exec_result.rc == :ok, do: true, else: false),
      refid: instruct.ref,
      instruct: instruct
    }

    ao = if(result.rc == :accepted, do: %AutoOff{ao | mode: :settling}, else: ao)

    {update(ao, instruct), {instruct.exec_result.rc, result}}
  end

  def execute(%AutoOff{} = ao, %ExecCmd{} = ec, _from) do
    result = %ExecResult{name: ao.name, cmd: ec.cmd}

    cond do
      ao.mode in [:settling, :autooff] and ec.cmd == "on" ->
        {ao, {:ok, %ExecResult{result | rc: :ok}}}

      ao.mode != :ready ->
        {ao, {:failed, %ExecResult{result | rc: :not_ready}}}

      ec.cmd != "on" ->
        {ao, {:failed, %ExecResult{result | rc: :unsupported_cmd}}}

      true ->
        {ao, {:failed, %ExecResult{result | rc: :error}}}
    end
  end

  def handle_instruct(%AutoOff{} = ao, %Instruct{} = instruct) do
    ao.instruct |> Instruct.expired(instruct) |> update(%AutoOff{ao | mode: :autoff})
  end

  def handle_notify(%AutoOff{} = ao, %Memo{}, :starting), do: ao

  def handle_notify(%AutoOff{} = ao, %Memo{} = memo, _mode) do
    cond do
      ao.equipment.name == memo.name ->
        Equipment.update_status(ao.equipment) |> update(ao)

      is_map_key(ao.watch, memo.name) ->
        status = Alfred.status(memo.name)

        %AutoOff{ao | watch: %{ao.watch | memo.name => status.cmd}}

      true ->
        ao
    end
  end

  def handle_release(%AutoOff{instruct: instruct} = ao, %TrackerEntry{} = te) do
    if is_struct(instruct) and instruct.exec_result.refid == te.refid do
      # the iniitial "on" command has been released
      instruct |> Instruct.released(te) |> update(ao)
    else
      # the subsequent auto off command has been released, clear the on instruction
      %AutoOff{ao | instruct: :none}
    end
  end

  def mode(%AutoOff{mode: prev_mode} = v, mode) do
    v = %AutoOff{v | mode: mode}
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

    %AutoOff{
      name: cfg[:name],
      mod: opts.server.name,
      equipment: equipment,
      names: Names.new([equipment.name] ++ cfg[:watch]),
      watch: for(name <- cfg[:watch], into: %{}, do: {name, "unknown"}),
      settle_for: cfg[:settle],
      valid?: true
    }
    |> calc_settle_ms()
  end

  def status(%AutoOff{} = ao, _opts) do
    %MutStatus{
      name: ao.name,
      good?: ao.equipment.status.good?,
      cmd: ao.equipment.status.cmd,
      extended: ao,
      status_at: DateTime.utc_now()
    }
  end

  defp calc_settle_ms(%AutoOff{settle_for: settle_for} = ao) when is_binary(settle_for) do
    settle_ms = Duration.parse!(settle_for) |> Duration.to_milliseconds() |> trunc()
    %AutoOff{ao | settle_ms: settle_ms}
  rescue
    _ ->
      Logger.warn("could not convert '#{settle_for}' to milliseconds")
      ao
  end

  defp calc_settle_ms(%AutoOff{} = ao), do: ao

  defp reset_watch(%AutoOff{watch: watch} = ao) do
    %AutoOff{ao | watch: for({k, _v} <- watch, into: %{}, do: {k, "unknown"})}
  end

  defp update(%Equipment{} = x, %AutoOff{} = v), do: %AutoOff{v | equipment: x}
  defp update(%AutoOff{} = v, %Instruct{} = x), do: %AutoOff{v | instruct: x}
  defp update(%Instruct{} = x, %AutoOff{} = v), do: %AutoOff{v | instruct: x}
end

defimpl Eva.Variant, for: Eva.AutoOff do
  alias Alfred.ExecCmd
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.AutoOff

  def control(%AutoOff{} = ao, %Memo{} = memo, mode), do: AutoOff.control(ao, memo, mode)
  def execute(%AutoOff{} = ao, %ExecCmd{} = ec, from), do: AutoOff.execute(ao, ec, from)
  def handle_instruct(%AutoOff{} = ao, instruct), do: AutoOff.handle_instruct(ao, instruct)
  def handle_notify(%AutoOff{} = ao, %Memo{} = memo, mode), do: AutoOff.handle_notify(ao, memo, mode)
  def handle_release(%AutoOff{} = ao, %TrackerEntry{} = te), do: AutoOff.handle_release(ao, te)
  def status(%AutoOff{} = ao, opts), do: AutoOff.status(ao, opts)
end
