defmodule UI.HelenChannel do
  @moduledoc """
  Handle socket messages for the Helen Channel
  """

  use Phoenix.Channel, log_join: false, log_handle_in: false

  def join("helen:admin", _message, socket) do
    {:ok, socket}
  end

  def join("room:" <> _private_room_id, _params, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  def handle_in(
        "button_click",
        %{"id" => id, "active_page" => active_page} = _req_payload,
        socket
      ) do
    socket = socket |> assign(:active_page, active_page)

    {:reply, {:refresh_page, %{id: id, active_page: active_page}}, socket}
  end

  def handle_in("button_click", _req_payload, socket) do
    {:reply, {:nop, %{}}, socket}
  end

  def handle_in("module_config_click", %{"module" => mod_bin}, socket) do
    alias Reef.Captain

    case mod_bin do
      "Reef.Captain.Server" ->
        {:reply,
         {:module_config_click_reply, %{module: mod_bin, opts: Captain.Opts.default_opts()}},
         socket}

      mod_bin ->
        {:reply, {:module_config_click_reply, %{module: mod_bin, opts: "not implemented"}},
         socket}
    end
  end

  def handle_in(msg, %{"subsystem" => subsystem}, socket)
      when msg in ["refresh_page", "page_loaded"] do
    base_resp = %{active_page: subsystem}

    case subsystem do
      "reef" -> socket |> reply_reef_status_map(base_resp)
      "roost" -> socket |> reply_roost_status_map(base_resp)
      "module-config" -> socket |> reply_mod_config_status_map(base_resp)
      "home" -> socket |> reply_home_status_map(base_resp)
    end
  end

  def handle_in("reef_click", payload, socket) do
    alias UI.ReefView

    base_resp = ReefView.button_click(payload)

    socket
    |> reply_reef_status_map(base_resp)
  end

  def handle_in("roost_click", %{"mode" => mode, "action" => action} = payload, socket)
      when mode in ["dance", "leaving", "closed"] and action in ["off", "play", "stop"] do
    alias UI.RoostView

    base_resp = RoostView.button_click(payload)

    socket
    |> reply_roost_status_map(base_resp)
  end

  # roost_click unmatched mode / action
  def handle_in("roost_click", payload, socket),
    do: {:reply, {:error, %{roost_click: payload}}, socket}

  def handle_in(type, payload, socket) do
    """
    handle_in(#{type}, #{inspect(payload, pretty: true)})
    """
    |> IO.puts()

    {:reply, {:nop, %{}}, socket}
  end

  defp reply_home_status_map(socket, base_resp) do
    {:reply, {:home_status, Map.merge(base_resp, %{})}, socket}
  end

  defp reply_mod_config_status_map(socket, base_resp) do
    {:reply, {:module_config_status, Map.merge(base_resp, %{hello: "doctor"})}, socket}
  end

  defp reply_reef_status_map(socket, base_resp) do
    alias UI.ReefView

    reef_status = ReefView.status()
    full_resp = Map.merge(base_resp, reef_status)

    {:reply, {:reef_status, full_resp}, socket}
  end

  defp reply_roost_status_map(socket, base_resp) do
    alias UI.RoostView

    {:reply, {:roost_status, Map.merge(base_resp, RoostView.status())}, socket}
  end
end
