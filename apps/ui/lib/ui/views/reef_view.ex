defmodule UI.ReefView do
  use UI, :view

  @doc false
  def button_click(%{
        "subsystem" => "reef",
        "action" => "manual-control",
        "value" => manual_control
      }) do
    alias Reef.Captain.Server, as: Captain

    server_mode = if manual_control, do: :standby, else: :active

    rc = Captain.server(server_mode)

    %{button_click: %{action: "manual_control"}} |> populate_click_rc(rc)
  end

  def button_click(%{"subsystem" => "reef", "step" => step}) do
    resp = %{button_click: %{step: step}}
    rc = Reef.mode(String.to_atom(step))

    resp |> populate_click_rc(rc)
  end

  def button_click(%{"subsystem" => "reef", "action" => action} = payload) do
    resp = %{button_click: %{action: action}}

    rc = button_handle_worker_and_action("captain", action, payload)

    resp |> populate_click_rc(rc)
  end

  def button_click(%{"subsystem" => "reef", "device" => device} = payload) do
    resp = %{button_click: %{device: device}}

    rc = button_handle_worker_and_device("captain", device, payload)

    resp |> populate_click_rc(rc)
  end

  def button_click(catchall) do
    resp = %{button_click: %{catchall: catchall}}

    resp |> populate_click_rc(:error)
  end

  def button_handle_worker_and_action(worker, action, payload) do
    alias Reef.Captain.Server, as: Captain
    alias Reef.FirstMate.Server, as: FirstMate

    case {worker, action} do
      {"captain", "reset"} -> Captain.restart()
      {"captain", "stop"} -> Captain.all_stop()
      {"captain", "unlock-steps"} -> {:noted, :unlock_steps}
      {"captain", "lock-steps"} -> {:noted, :lock_steps}
      {"first_mate", "reset"} -> FirstMate.restart()
      {"first_mate", "off"} -> FirstMate.server(:standby)
      _x -> {:unhandled_worker_action, payload}
    end
  end

  def button_handle_worker_and_device(worker, device, payload) do
    alias Reef.MixTank.{Air, Pump, Rodi}
    # alias Reef.MixTank.Temp, as: Heater

    case {worker, device} do
      {"captain", "water_pump"} -> Pump.toggle()
      {"captain", "air_pump"} -> Air.toggle()
      {"captain", "rodi_valve"} -> Rodi.toggle()
      {"captain", "heater"} -> :not_permitted
      _x -> {:unhandled_worker_device, payload}
    end
  end

  def status do
    Reef.status()
  end

  defp populate_click_rc(resp, click_rc) do
    case click_rc do
      {rc, anything} when is_atom(rc) ->
        resp
        |> put_in([:button_click, :rc], rc)
        |> put_in([:button_click, :rc_str], inspect(anything, pretty: true))

      rc when is_atom(rc) ->
        resp |> put_in([:button_click, :rc], Atom.to_string(rc))

      rc when is_binary(rc) ->
        resp |> put_in([:button_click, :rc], rc)

      rc ->
        resp |> put_in([:button_click, :rc], inspect(rc, pretty: true))
    end
  end
end
