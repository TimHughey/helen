defmodule MessageSave do
  @moduledoc """
  """

  require Logger
  use GenServer
  use Timex
  use Timex.Ecto.Timestamps
  use Ecto.Schema

  import Application, only: [get_env: 3]
  import Process, only: [send_after: 3]
  import Ecto.Query, only: [from: 2]
  import Repo, only: [delete_all: 1, one!: 1, insert!: 1]

  schema "message" do
    field(:direction, :string)
    field(:payload, :string)
    field(:dropped, :boolean)

    timestamps(usec: true)
  end

  def message_count do
    from(ms in MessageSave, select: count(ms.id)) |> one!()
  end

  @runtime_opts_msg :runtime_opts_msg
  def runtime_opts, do: GenServer.call(MessageSave, {@runtime_opts_msg})

  @save_msg :save_msg
  def save(direction, payload, dropped \\ false) when direction in [:in, :out] do
    GenServer.cast(MessageSave, {@save_msg, direction, payload, dropped})
  end

  @set_save_msg :set_save_msg
  def set_save(val) when is_boolean(val) do
    GenServer.call(MessageSave, {@set_save_msg, val})
  end

  @startup_msg {:startup}
  def init(s) when is_map(s) do
    if s.autostart, do: send_after(self(), @startup_msg, 0)
    Logger.info(fn -> "init()" end)

    {:ok, s}
  end

  def start_link(args) do
    defs = [save: false, delete_older_than_hrs: 12]
    opts = get_env(:mcp, MessageSave, defs) |> Enum.into(%{})

    s = Map.put(args, :opts, opts)
    GenServer.start_link(MessageSave, s, name: MessageSave)
  end

  def terminate(reason, _state) do
    Logger.info(fn -> "terminating with reason #{inspect(reason)}" end)
  end

  def handle_call({@runtime_opts_msg}, _from, s) do
    {:reply, s.opts, s}
  end

  def handle_call({@set_save_msg, val}, _from, s) do
    new_opts = Map.put(s.opts, :save, val)
    s = Map.put(s, :opts, new_opts)
    {:reply, :ok, s}
  end

  def handle_cast({@save_msg, _, _, _}, %{opts: %{save: false}} = s) do
    {:noreply, s}
  end

  def handle_cast({@save_msg, direction, payload, dropped}, %{opts: %{save: true}} = s) do
    %MessageSave{direction: Atom.to_string(direction), payload: payload, dropped: dropped}
    |> insert!()

    older_dt =
      Timex.to_datetime(Timex.now(), "UTC")
      |> Timex.shift(hours: s.opts.delete_older_than_hrs * -1)

    from(ms in MessageSave, where: ms.inserted_at < ^older_dt)
    |> delete_all()

    {:noreply, s}
  end

  def handle_info(@startup_msg, s) do
    opts = Map.get(s, :opts)
    Logger.info(fn -> "startup(), opts: #{inspect(opts)}" end)

    {:noreply, s}
  end
end