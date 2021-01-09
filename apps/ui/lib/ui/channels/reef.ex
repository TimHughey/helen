defmodule UI.Channel.Handler.Reef do
  @moduledoc false

  alias Phoenix.Socket
  alias UI.ReefView

  def add_status(resp \\ %{}), do: put_in(resp, [:status], ReefView.status())

  def click(payload, %{assigns: _assigns} = socket) do
    ReefView.button_click(payload, socket)
    |> add_status()
    |> reply()
  end

  def join(socket) do
    socket
  end

  def live_update(%Socket{assigns: assigns}) do
    base_msg = Map.take(assigns, [:live_update])

    add_status(base_msg)
  end

  def page_loaded(socket) do
    add_status()
    |> reply(socket)
  end

  def reply(%{socket: %Socket{} = socket} = resp) do
    reply(Map.drop(resp, [:socket]), socket)
  end

  def reply(response, %Socket{} = socket), do: {:reply, {:reef, response}, socket}
  def reply(%Socket{} = socket, response), do: reply(response, socket)
end
