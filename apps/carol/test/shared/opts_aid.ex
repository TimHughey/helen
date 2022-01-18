defmodule Carol.OptsAid do
  @moduledoc false

  @tz "America/New_York"

  def add(ctx) do
    equipment = ctx[:equipment] || "unspecified"
    tz = ctx[:timezone] || @tz
    ref_dt_fn = ctx[:ref_dt_dn] || fn -> Timex.now(tz) end
    ref_dt = ref_dt_fn.()

    # NOTE: ref_dt is used downstream to create 'now' datetimes so it
    # must be earlier than datetime
    # ref_dt = Timex.shift(datetime, microseconds: -1)

    %{opts: [equipment: equipment, ref_dt: ref_dt, timezone: tz], ref_dt: ref_dt}
  end
end
