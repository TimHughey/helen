defmodule Rena.HoldCmd.Server do
  require Logger
  use GenServer

  alias __MODULE__
  alias Alfred.Notify.Memo
  alias Broom.TrackerEntry
  alias Rena.HoldCmd.{Cmd, State}

  @impl true
  def init(args) when is_list(args) or is_map(args) do
    if args[:server_name] do
      Process.register(self(), args[:server_name])
      {:ok, State.new(args), {:continue, :bootstrap}}
    else
      {:stop, :missing_server_name}
    end
  end

  def child_spec(opts) do
    {id, opts_rest} = Keyword.pop(opts, :id)
    {restart, opts_rest} = Keyword.pop(opts_rest, :restart, :permanent)

    final_opts = [server_name: id] ++ opts_rest

    %{id: id, start: {Server, :start_link, [final_opts]}, restart: restart}
  end

  def start_link(start_args) do
    GenServer.start_link(Server, start_args)
  end

  @impl true
  def handle_call(:pause, _from, %State{} = s) do
    State.pause_notifies(s) |> reply_ok()
  end

  @impl true
  def handle_call(:resume, _from, %State{} = s) do
    State.start_notifies(s) |> reply_ok()
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = s) do
    State.start_notifies(s) |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  @impl true
  def handle_info({Alfred, %Memo{missing?: true} = memo}, %State{} = s) do
    s
    |> Betty.app_error(equipment: memo.name, missing: true)
    |> State.update_last_notify_at()
    |> noreply()
  end

  @impl true
  def handle_info({Alfred, %Memo{} = memo}, %State{} = s) do
    opts = [alfred: s.alfred, server_name: s.server_name]

    memo
    |> Cmd.hold(s.hold_cmd, opts)
    |> State.update_last_exec(s)
    |> State.update_last_notify_at()
    |> noreply()
  end

  @impl true
  def handle_info({Broom, %TrackerEntry{acked: true}}, s) do
    {:ok, s.hold_cmd.cmd}
    |> State.update_last_exec(s)
    |> State.update_last_notify_at()
    |> noreply()
  end

  @impl true
  def handle_info({Broom, %TrackerEntry{}}, s) do
    # tracked commands are logged prior to receipt of the TrackerEntry,
    # no need to log further
    noreply(s)
  end

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply({:stop, :normal, s}), do: {:stop, :normal, s}

  defp reply_ok(%State{} = s), do: {:reply, :ok, s}
end
