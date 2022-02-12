defmodule Carol.OptsAid do
  @moduledoc false

  @tz "America/New_York"

  def add(ctx) do
    equipment = ctx[:equipment] || "unspecified"
    tz = ctx[:timezone] || @tz
    ref_dt = Timex.now(tz)

    %{opts: [equipment: equipment, ref_dt: ref_dt, timezone: tz], ref_dt: ref_dt}
  end
end
