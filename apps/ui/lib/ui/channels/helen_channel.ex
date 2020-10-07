defmodule UI.HelenChannel do
  @moduledoc """
  Handle socket messages for the Helen Channel
  """

  require Logger

  use Phoenix.Channel, log_join: false, log_handle_in: false
  alias Phoenix.Socket

  def join("helen:admin", _message, socket) do
    {:ok, socket}
  end

  def join("helen:reef", _message, %{assigns: assigns} = socket) do
    alias UI.Channel.Handler.Reef
    # Logger.info("join helen:reef #{inspect(message)}")
    # Logger.info("socket: #{inspect(socket, pretty: true)}")

    if is_nil(get_in(assigns, [:live_update])) do
      Process.send_after(self(), {:live_update, "reef"}, 100)

      {:ok, Reef.join(Socket.assign(socket, :live_update, true))}
    else
      {:ok, Reef.join(socket)}
    end
  end

  def join("helen:roost", _message, socket) do
    alias UI.Channel.Handler.Roost
    # Logger.info("join helen:reef #{inspect(message)}")
    # Logger.info("socket: #{inspect(socket, pretty: true)}")

    {:ok, Roost.join(socket)}
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

  def handle_in("module_config_click", msg, socket) do
    import UI.ModuleConfigView, only: [button_click: 2]

    {:reply, {:module_config_click_reply, button_click(msg, socket)}, socket}
  end

  def handle_in(msg, %{"subsystem" => subsystem}, socket)
      when msg in ["refresh_page", "page_loaded"] do
    alias UI.Channel.Handler.{Reef, Roost}

    base_resp = %{active_page: subsystem}

    case subsystem do
      "reef" -> Reef.page_loaded(socket)
      "roost" -> Roost.page_loaded(socket)
      "module-config" -> socket |> reply_mod_config_status_map(base_resp)
      "home" -> socket |> reply_home_status_map(base_resp)
    end
  end

  def handle_in("reef_click", payload, socket) do
    alias UI.Channel.Handler.Reef

    Reef.click(payload, socket)
  end

  def handle_in("roost_click", payload, socket) do
    alias UI.Channel.Handler.Roost

    Roost.click(payload, socket)
  end

  def handle_in(type, payload, socket) do
    Logger.info("""
    unmatched handle_in(#{type}, #{inspect(payload, pretty: true)})
    """)

    {:reply, {:nop, %{}}, socket}
  end

  def handle_info({:live_update, subsystem}, %{assigns: %{live_update: live_update}} = socket) do
    alias UI.Channel.Handler.Reef

    if subsystem == "reef" and live_update do
      push(socket, "live_update", Reef.live_update(socket))

      Process.send_after(self(), {:live_update, subsystem}, 1500)
    end

    {:noreply, socket}
  end

  defp reply_home_status_map(socket, base_resp) do
    {:reply, {:home_status, Map.merge(base_resp, %{})}, socket}
  end

  defp reply_mod_config_status_map(socket, base_resp) do
    {:reply, {:module_config_status, Map.merge(base_resp, %{hello: "doctor"})}, socket}
  end

  def reply(%Socket{} = socket, response) do
    {:reply, response, socket}
  end

  def reply(response, %Socket{} = socket) do
    {:reply, response, socket}
  end
end
