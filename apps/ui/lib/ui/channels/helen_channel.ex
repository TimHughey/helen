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
        %{"value" => value, "id" => id} = _req_payload,
        socket
      ) do
    alias Phoenix.View
    alias UI.ReefView

    if String.contains?(id, "reef_mode") do
      rc = handle_worker_mode_button(value)
      reef_state = Reef.x_state()
      specifics_html = View.render_to_string(ReefView, "specifics.html", reef_state: reef_state)

      resp_payload = %{page: "reef", rc: inspect(rc), reef_specifics_html: specifics_html}

      {:reply, {:ok, resp_payload}, socket}
    else
      {:reply, {:error, %{reason: "not a worker"}}, socket}
    end
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
