defmodule UI.RoostView do
  use UI, :view

  def button_click(%{"mode" => mode, "action" => action}) do
    resp = %{
      button_click: %{
        mode: mode,
        action: action
      }
    }

    case button_handle_mode_and_action(mode, action) do
      {rc, mode} ->
        resp
        |> put_in([:button_click, :rc], rc)
        |> put_in([:button_click, :rc_str], inspect({rc, mode}, pretty: true))

      rc ->
        resp |> put_in([:button_click, :rc], rc)
    end
  end

  def button_handle_mode_and_action(mode, action) do
    case {mode, action} do
      {mode, "play"} -> map_mode(mode) |> Roost.mode([])
      {_mode, "off"} -> Roost.restart()
      {_mode, "stop"} -> Roost.all_stop()
    end
  end

  def status do
    modes = Roost.available_modes()
    state = Roost.x_state()

    for mode <- modes, reduce: %{modes: []} do
      %{modes: modes} = status ->
        mode_status = %{
          mode: map_mode(mode),
          status: get_in(state, [mode, :status]) |> map_mode_status()
        }

        modes = [modes, [mode_status]] |> List.flatten()

        status |> put_in([:modes], modes)
    end
  end

  def map_mode(mode) do
    case mode do
      :dance_with_me -> :dance
      "dance" -> :dance_with_me
      :leaving -> :leaving
      :closed -> :closed
      "closed" -> :closed
    end
  end

  def map_mode_status(status) do
    case status do
      :running -> :play
      :completed -> :stop
      :ready -> :off
    end
  end
end
