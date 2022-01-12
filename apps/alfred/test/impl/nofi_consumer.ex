defmodule Alfred.NofiConsumer do
  @moduledoc false

  defstruct name: nil, caller_pid: nil, name_pid: nil, ticket: nil

  use GenServer

  def info(pid), do: GenServer.call(pid, {:info})
  def trigger(pid), do: GenServer.call(pid, {:just_saw})

  @name_opts Alfred.Name.allowed_opts()
  @notify_opts Alfred.Notify.allowed_opts()
  @impl true
  def init(init_args) do
    {name_opts, args_rest} = Keyword.split(init_args, @name_opts)
    {notify_opts, fields} = Keyword.split(args_rest, @notify_opts)

    name = fields[:name]

    {:ok, name_pid} = Alfred.Name.register(name, name_opts)
    {:ok, ticket} = Alfred.Notify.register(name, notify_opts)

    {:ok, struct(%__MODULE__{}, [name_pid: name_pid, ticket: ticket] ++ fields)}
  end

  def start_link(args) do
    name_opts = Enum.into(args, []) |> Keyword.put_new(:type, :mut)

    %{name: name} = Alfred.NamesAid.name_add(%{name_add: name_opts})

    init_args = [name: name, caller_pid: self()] ++ name_opts

    GenServer.start_link(__MODULE__, init_args)
  end

  @impl true
  def handle_call({:info}, _from, state), do: make_info_map(state) |> reply(state)

  @impl true
  def handle_call({:just_saw}, _from, %{name: name} = state) do
    :ok = Alfred.Name.register(name, [])

    reply(:ok, state)
  end

  @impl true
  def handle_info({Alfred, %Alfred.Memo{} = memo}, state) do
    msg = {memo, make_info_map(state)}

    :ok = Process.send(state.caller_pid, msg, [])

    noreply(state)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def make_info_map(%{ticket: %{ref: ref}} = state) do
    extras = %{server_pid: self(), seen_at: Alfred.Notify.seen_at(ref)}

    Map.from_struct(state) |> Map.merge(extras)
  end

  def noreply(state), do: {:noreply, state}
  def reply(result, %__MODULE__{} = state), do: {:reply, result, state}
end
