defmodule UI.ReefView do
  use UI, :view

  import List, only: [flatten: 1]

  alias Reef.Captain.Server, as: Captain
  alias Reef.FirstMate.Server, as: FirstMate

  def button_click(%{"action" => "live-update"}, socket) do
    %{socket: socket}
  end

  @doc false
  def button_click(%{"worker" => worker} = payload, socket) do
    case payload do
      %{"action" => "manual-control"} -> manual_control(worker, socket)
      %{"action" => "reset"} -> restart(worker, socket)
      %{"action" => "stop"} -> worker_mode(worker, :all_stop, socket)
      %{"mode" => mode} -> worker_mode(worker, mode, socket)
      %{"subworker" => sub} -> subworker_toggle(worker, sub, socket)
      payload -> unhandled_click(payload, socket)
    end
  end

  @doc false
  def button_click(payload, socket), do: unhandled_click(payload, socket)

  @doc false
  def manual_control(worker, socket) do
    mod = worker_mod(worker)

    {rc, server_mode} = mod.manual_control()

    %{ui: %{worker: worker, manual_control: server_mode == :manual_control}, socket: socket}
    |> click_rc(rc)
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

    %{
      ui: %{worker: worker, mode: mode, modes_locked: true},
      socket: socket_put(socket, :modes_locked, true)
    }
    |> click_rc(rc)
  end

  def socket_get(%{assigns: assigns}, what), do: get_in(assigns, flatten([what]))

  def socket_put(socket, what, val) do
    import Phoenix.Socket, only: [assign: 3]

    assign(socket, what, val)
  end

  def status do
    Reef.status()
  end

  def subworker_toggle(worker, subworker, socket) do
    mod =
      case worker do
        "captain" -> Reef.Captain
        "first_mate" -> Reef.FirstMate
      end

    rc = apply(mod, :subworker_toggle, [subworker])

    %{ui: %{worker: worker, subworker: subworker, toggle: true}, socket: socket}
    |> click_rc(rc)
  end

  def unhandled_click(payload, socket) do
    resp = %{ui: %{unhandled_click: true, payload: payload}, socket: socket}

    IO.puts(inspect(resp, pretty: true))

    resp
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
      "captain" -> Captain
      "first_mate" -> FirstMate
      _no_match -> :unmatched_worker
    end
  end
end
