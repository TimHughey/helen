defmodule Alfred.NofiConsumer do
  @moduledoc false

  defstruct dev_alias: nil, caller_pid: nil, ticket: nil

  use GenServer

  def info(pid), do: GenServer.call(pid, {:info})
  def trigger(pid), do: GenServer.call(pid, {:trigger})

  @notify_opts Alfred.Notify.allowed_opts()
  @impl true
  def init(init_args) do
    dev_alias = Keyword.get(init_args, :dev_alias)
    {notify_opts, fields} = Keyword.split(init_args, @notify_opts)

    _dev_alias = Alfred.DevAlias.register(dev_alias, [])
    {:ok, ticket} = Alfred.Notify.register(dev_alias.name, notify_opts)

    {:ok, struct(%__MODULE__{}, [ticket: ticket] ++ fields)}
  end

  def start_link(args) do
    name_opts = Enum.into(args, [])

    dev_alias = Alfred.NamesAid.new_dev_alias(:equipment, type: :mut)

    init_args = [dev_alias: dev_alias, caller_pid: self()] ++ name_opts

    GenServer.start_link(__MODULE__, init_args)
  end

  @impl true
  def handle_call({:info}, _from, state), do: {:reply, make_info_map(state), state}

  @impl true
  def handle_call({:trigger}, _from, %{dev_alias: dev_alias} = state) do
    dev_alias = Alfred.DevAlias.ttl_reset(dev_alias)
    _dev_alias = Alfred.DevAlias.register(dev_alias, [])

    {:reply, :ok, struct(state, dev_alias: dev_alias)}
  end

  @impl true
  def handle_info({Alfred, %Alfred.Memo{} = memo}, state) do
    msg = {memo, make_info_map(state)}

    :ok = Process.send(state.caller_pid, msg, [])

    {:noreply, state}
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def make_info_map(%{dev_alias: dev_alias, ticket: %{ref: ref}} = state) do
    extras = %{name: dev_alias.name, server_pid: self(), seen_at: Alfred.Notify.seen_at(ref)}

    Map.from_struct(state) |> Map.merge(extras)
  end
end
