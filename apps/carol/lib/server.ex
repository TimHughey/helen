defmodule Carol.Server do
  @moduledoc false

  require Logger
  use GenServer

  alias __MODULE__
  alias Alfred.Notify.Memo
  alias Carol.{Playlist, Program, State}

  @impl true
  def init(args) do
    init_args_fn = args[:init_args_fn]
    server_name = args[:server_name]

    if server_name do
      Process.register(self(), server_name)

      # NOTE:
      # 1. init_args_fn, when available, is the sole provider of args so
      #    we must add server_name to the returned args
      #
      # 2. otherwise simply use the args passed in

      if(init_args_fn, do: init_args_fn.(server_name: server_name), else: args)
      |> then(fn final_args -> {:ok, State.new(final_args), {:continue, :bootstrap}} end)
    else
      {:stop, :missing_server_name}
    end
  end

  @doc """
  Safely call a server instance

  Wraps a `GenServer.call/3` in a try/catch.

  Returns the result of the `GenServer.call/3` or `{:no_server, server_name}`
  """
  def call(server, msg) when is_pid(server) or is_atom(server) do
    GenServer.call(server, msg)
  rescue
    _ -> {:no_server, server}
  catch
    :exit, _ -> {:no_server, server}
  end

  @doc """
  Create the child spec map for a server instance

  This function accepts a comingled list of `child_spec` opts and server
  initialization opts.

  The `child_spec` keys are extracted from the list to create the `child_spec`
  map and the remaining keys are passed as initialization opts.

  > Server initialization opts can not conflict with `child_spec` opts.
  >
  > See `Supervisor.child_spec/2` for the shape and description of a
  > child spec map.

  """

  def child_spec(opts) do
    # :id is for the Supervisor so remove it from opts
    {id, opts_rest} = Keyword.pop(opts, :id)

    # GenServer restart and shutdown are also important to the Supervisor
    {server_opts, opts_rest} = Keyword.split(opts_rest, [:restart, :shutdown])

    # init/1 requires server_name, add to opts
    final_opts = Keyword.put(opts_rest, :server_name, id)

    # make server_opts a map so it can be merged into the final child spec
    server_opts_map = Enum.into(server_opts, %{})

    # build the final child_spec map
    # See Supervisor.
    %{id: id, start: {Server, :start_link, [final_opts]}} |> Map.merge(server_opts_map)
  end

  @doc false
  def start_link(start_args) when is_list(start_args) do
    GenServer.start_link(Server, start_args)
  end

  # GenServer handlers

  @impl true
  def handle_call(:restart, _from, %State{} = s) do
    {:stop, :normal, :restarting, s}
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = s) do
    # NOTE: State.refresh_programs/1 ensures all programs are valid

    s
    |> State.refresh_programs()
    |> State.start_notifies()
    |> noreply()

    # NOTE: at this point the server is running and no further actions
    # occur until an equipment notification is received
  end

  # @impl true
  # @id_msgs [:start_id, :finish_id]
  # def handle_continue({id_msg, id}, %State{} = s) when id_msg in @id_msgs and is_binary(id) do
  #   continue(s, :programs)
  # end

  @impl true
  def handle_continue(:programs, %State{} = s) do
    s
    |> State.refresh_programs()
    |> then(fn new_state -> {Playlist.active_id(new_state.playlist), new_state} end)
    |> execute()
    |> noreply()
  end

  @impl true
  @info_types [:finish_id, :start_id]
  def handle_info({type, _id}, %State{} = s) when type in @info_types do
    # NOTE: no special handling for starting or finishing an id
    continue(:programs, s)
  end

  @impl true
  def handle_info({Alfred, %Memo{missing?: true} = memo}, %State{} = s) do
    [server_name: s.server_name, equipment: memo.name, missing: true]
    |> Betty.app_error_v2(passthrough: s)
    |> State.update_notify_at()
    |> noreply()
  end

  @impl true
  def handle_info({Alfred, _memo}, %State{} = s) do
    # NOTE: reuse :prgrams to ensure equipment cmd is proper
    continue(:programs, s)
  end

  @impl true
  def handle_info({Broom, te}, %State{exec_result: er} = s) do
    # handle released cmds and store cmd in the State when:
    #  * matched refids
    #  * unmatched refids

    case {te, er} do
      {%{refid: refid}, %{refid: refid}} -> te.cmd
      {_, %{refid: refid}} -> {:unexpected_refid, refid}
    end
    |> State.save_cmd(s)
    |> noreply()
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp execute(%Alfred.ExecCmd{} = ec, %State{alfred: alfred} = s) do
    alfred.execute(ec) |> State.save_exec_result(s)
  end

  defp execute({id, %State{} = s}) when is_binary(id) do
    Program.cmd_for_id(id, s.programs, s.equipment) |> execute(s)
  end

  defp execute({:keep, s}), do: State.save_exec_result(:keep, s)

  defp execute({:none, s}) do
    opts = [name: s.equipment, cmd: "off", notify: true]

    Alfred.ExecCmd.new(opts) |> execute(s)
  end

  # GenServer reply helpers

  defp continue(term, %State{} = s), do: {:noreply, s, {:continue, term}}
  # defp continue_id(type, id, %State{} = s), do: {:noreply, s, {:continue, {type, id}}}
  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply({:stop, :normal, s}), do: {:stop, :normal, s}
end
