defmodule Garden.State do
  alias __MODULE__
  alias Garden.Config
  alias Garden.Equipment

  defstruct cfg: nil, mode: :init, check: nil, wakeup_timer: nil, token: 1

  def change_token(%State{token: token} = s), do: %State{s | token: token + 1}

  def mode(%State{} = s, next_mode), do: %State{s | mode: next_mode}

  def new(%Config{irrigation_power: irrigation_power} = cfg) do
    needed_equipment = [irrigation_power] ++ Config.equipment(cfg)

    %State{cfg: cfg, check: Equipment.Check.new(needed_equipment)}
  end

  def update(%Config{} = cfg, %State{} = s), do: %State{s | cfg: cfg}
  def update(%Equipment.Check{} = check, %State{} = s), do: %State{s | check: check}
  def update_wakeup_timer(ref, %State{} = s), do: %State{s | wakeup_timer: ref}
end
