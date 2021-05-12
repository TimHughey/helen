defmodule Alfred.NotifyServer do
  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.{KnownName, NotifyTo}
  alias Alfred.NotifyServer, as: Mod
  alias Alfred.NotifyServerState, as: State

  @impl true
  def init(_args) do
    %State{} |> reply_ok()
  end

  def start_link(_opts) do
    Logger.debug(["starting ", inspect(Mod)])
    GenServer.start_link(__MODULE__, [], name: Mod)
  end

  @impl true
  def handle_call({:names_registered}, _from, %State{} = s) do
    name_registrations(s) |> reply(s)
  end

  @impl true
  def handle_call({:register, name, interval_ms}, {pid, _ref}, %State{} = s) do
    register(name, pid, interval_ms, s) |> reply()
  end

  @impl true
  def handle_cast({:seen_list, seen_list}, %State{} = s) do
    notify(seen_list, s) |> noreply()
  end

  ##
  ## Private
  ##

  defp name_registrations(%State{} = s) do
    for {name, _regs} <- s.registrations, do: name
  end

  defp notify(seen_list, s) do
    for %KnownName{name: name} <- seen_list, reduce: s do
      # we have registrations for this name
      # match the name in the registration list and notify
      %State{registrations: %{^name => name_regs}} = s ->
        revised_reg_list = notify_regs(name_regs, name)

        # update the state with the updated registrations for this name
        %{s | registrations: put_in(s.registrations, [name], revised_reg_list)}

      # no registrations for name, pass through state
      s ->
        s
    end
  end

  defp notify_regs(regs, name) do
    for %NotifyTo{interval_ms: interval_ms} = reg <- regs do
      utc_now = DateTime.utc_now()

      case DateTime.diff(utc_now, reg.last_notify) do
        x when x >= interval_ms -> notify_pid(reg, name)
        _x -> reg
      end
    end
    # flatten the results to remove dead pid registrations
    |> List.flatten()
  end

  # (1 of 2) NotifyTo entry has a pid
  defp notify_pid(%NotifyTo{pid: pid} = reg, name) when is_pid(pid) do
    if Process.alive?(pid) do
      send(pid, {Alfred, reg.ref, {:notify, name}})
      %NotifyTo{reg | last_notify: DateTime.utc_now()}
    else
      Logger.debug([inspect(pid), " exit: removing ", name, " registration"])
      []
    end
  end

  defp register(name, pid, opts, s) do
    ref = make_ref()

    notify_to = %NotifyTo{name: name, pid: pid, ref: ref, interval_ms: opts[:interval_ms]}

    regs_for_name =
      [notify_to, get_in(s.registrations, [name]) || []]
      |> List.flatten()
      |> Enum.dedup_by(fn %NotifyTo{pid: pid} -> pid end)

    all_regs = put_in(s.registrations, [name], regs_for_name)

    if opts[:link], do: Process.link(pid)

    {%{s | registrations: all_regs}, {:ok, notify_to}}
  end

  defp noreply(s), do: {:noreply, s}
  # defp reply(s, val) when is_map(s), do: {:reply, val, s}
  defp reply(val, %State{} = s), do: {:reply, val, s}
  defp reply({%State{} = s, val}), do: {:reply, val, s}
  defp reply_ok(s), do: {:ok, s}
end
