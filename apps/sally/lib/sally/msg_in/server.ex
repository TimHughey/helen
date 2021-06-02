defmodule Sally.MsgIn.Server do
  require Logger
  use GenServer

  alias Sally.MsgIn
  alias Sally.MsgIn.{Opts, Server, State}

  @impl true
  def init(%Opts{} = opts) do
    %State{opts: opts} |> reply_ok()
  end

  def start_link(%Opts{} = opts) do
    # assemble the genserver opts
    genserver_opts = [name: opts.server.name] ++ opts.server.genserver
    GenServer.start_link(Server, opts, genserver_opts)
  end

  @impl true
  def handle_cast(%MsgIn{} = mi, %State{} = s) do
    s.opts.callback_mod.handle_message(mi)

    noreply(s)
  end

  ##
  ## GenServer Reply Helpers
  ##

  # (1 of 2) handle plain %State{}
  defp noreply(%State{} = s), do: {:noreply, s}

  # (2 of 2) support pipeline {%State{}, msg} -- return State and discard message
  # defp noreply({%State{} = s, _msg}), do: {:noreply, s}

  # (1 of 4) handle pipeline: %State{} first, result second
  # defp reply(%State{} = s, res), do: {:reply, res, s}

  # (2 of 4) handle pipeline: result is first, %State{} is second
  # defp reply(res, %State{} = s), do: {:reply, res, s}

  # (3 of 4) assembles a reply based on a tuple (State, result) and rc
  # defp reply({%State{} = s, result}, rc), do: {:reply, {rc, result}, s}

  # (4 of 4) assembles a reply based on a tuple {result, State}
  # defp reply({%State{} = s, result}), do: {:reply, result, s}

  defp reply_ok(%State{} = s) do
    Logger.debug(["\n", inspect(s, pretty: true), "\n"])

    {:ok, s}
  end
end
