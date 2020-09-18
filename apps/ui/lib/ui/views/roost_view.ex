defmodule UI.RoostView do
  use UI, :view

  import List, only: [flatten: 1]

  @doc false
  def button_click(%{"worker" => worker, "mode" => mode} = payload, socket) do
    case payload do
      %{"action" => "live-update"} -> live_update(payload, socket)
      %{"action" => "play"} -> worker_mode(worker, mode, socket)
      %{"action" => "reset"} -> restart(worker, socket)
      %{"action" => "stop"} -> worker_mode(worker, :all_stop, socket)
    end
  end

  @doc false
  def button_click(payload, socket) do
    resp = %{ui: %{unhandled_click: true, payload: payload}, socket: socket}

    IO.puts(inspect(resp, pretty: true))

    resp
  end

  @doc false
  def live_update(%{"subsystem" => subsystem}, socket) do
    live_update? = socket_get(socket, :live_update)
    next_live_update? = not live_update?

    if next_live_update? do
      Process.send_after(self(), {:live_update, subsystem}, 1000)
    end

    %{
      ui: %{subsystem: subsystem, live_update: next_live_update?},
      socket: socket_put(socket, :live_update, next_live_update?)
    }
  end

  @doc false
  def restart(worker, socket) do
    mod = worker_mod(worker)

    rc = mod.restart()

    %{ui: %{worker: worker, restart: true}, socket: socket} |> click_rc(rc)
  end

  @doc false
  def worker_mode(worker, mode, socket) do
    to_atom = fn
      x when is_binary(x) -> String.to_atom(x)
      x when is_atom(x) -> x
      _x -> :not_atom
    end

    mod = worker_mod(worker)

    rc = mod.mode(to_atom.(mode), [])

    %{ui: %{worker: worker, mode: mode}, socket: socket}
    |> click_rc(rc)
  end

  def socket_get(%{assigns: assigns}, what), do: get_in(assigns, flatten([what]))

  def socket_put(socket, what, val) do
    import Phoenix.Socket, only: [assign: 3]

    assign(socket, what, val)
  end

  def status do
    Roost.status()
  end

  def click_rc(resp, rc) do
    case rc do
      {rc, anything} when is_atom(rc) ->
        update_in(resp, [:ui], fn x -> Map.put_new(x, :click, %{}) end)
        |> put_in([:ui, :click, :rc], rc)
        |> put_in([:ui, :click, :rc_str], inspect(anything, pretty: true))

      rc when is_atom(rc) ->
        update_in(resp, [:ui], fn x -> Map.put_new(x, :click, %{}) end)
        |> put_in([:ui, :click, :rc], Atom.to_string(rc))

      rc when is_binary(rc) ->
        update_in(resp, [:ui], fn x -> Map.put_new(x, :click, %{}) end)
        |> put_in([:ui, :click, :rc], rc)

      rc ->
        update_in(resp, [:ui], fn x -> Map.put_new(x, :click, %{}) end)
        |> put_in([:ui, :click, :rc], inspect(rc, pretty: true))
    end
  end

  def worker_mod(worker) do
    case worker do
      "roost" -> Roost
      _no_match -> :unmatched_worker
    end
  end
end
