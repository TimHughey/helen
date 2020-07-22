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
        %{"value" => value, "id" => id, "active_page" => active_page} = _req_payload,
        socket
      ) do
    alias Phoenix.View
    alias UI.ReefView
    alias UI.RoostView

    socket = socket |> assign(:active_page, active_page)

    cond do
      String.contains?(id, "reef_mode") ->
        rc = handle_worker_mode_button(value)
        reef_state = Reef.x_state()
        specifics_html = View.render_to_string(ReefView, "specifics.html", reef_state: reef_state)

        resp_payload = %{section: "reef-specifics", rc: inspect(rc), html: specifics_html}

        {:reply, {:refresh_section, resp_payload}, socket}

      String.contains?(id, "roost_mode") ->
        rc = handle_roost_worker_mode_button(value)
        roost_state = Roost.Server.x_state()

        specifics_html =
          View.render_to_string(RoostView, "specifics.html", roost_state: roost_state)

        resp_payload = %{
          section: "roost-specifics",
          rc: inspect(rc),
          html: specifics_html
        }

        {:reply, {:refresh_section, resp_payload}, socket}

      true ->
        {:reply, {:error, %{reason: "not a worker"}}, socket}
    end
  end

  def handle_in("button_click", _req_payload, socket) do
    {:reply, {:nop, %{}}, socket}
  end

  defp handle_roost_worker_mode_button(value) do
    alias Roost.Server, as: Server

    apply(Server, :worker_mode, [String.to_atom(value), []])
  end

  defp handle_worker_mode_button(value) do
    alias Reef.FirstMate.Server, as: FirstMate

    mode = String.to_atom(value)

    if mode == :clean do
      %{worker_mode: fm_mode} = FirstMate.x_state()

      case fm_mode do
        k when k in [:ready, :normal_operations] -> FirstMate.worker_mode(:clean, [])
        k when k in [:clean, :disable] -> FirstMate.worker_mode(:normal_operations, [])
        _k -> FirstMate.worker_mode(:normal_operations, [])
      end
    else
      apply(Reef, :worker_mode, [String.to_atom(value)])
    end
  end
end
