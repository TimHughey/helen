defmodule Carol.OptsAid do
  @moduledoc """
  Create the standard `opts` required for Carol modules

  Carol modules perform significant DateTime calculations and
  require points of reference passed through as opts.

  This module adds those essential opts for testing convenience.
  """

  @tz "America/New_York"

  def add(ctx) do
    tz = ctx[:timezone] || @tz
    datetime_fn = ctx[:datetime_fn] || fn -> Timex.now(tz) end
    datetime = datetime_fn.()

    # NOTE: ref_dt is used downstream to create 'now' datetimes so it
    # must be earlier than datetime
    ref_dt = Timex.shift(datetime, microseconds: -1)

    %{opts: [datetime: datetime, timezone: tz, equipment: "some name"], ref_dt: ref_dt}
  end
end
