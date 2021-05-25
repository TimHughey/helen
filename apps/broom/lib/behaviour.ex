defmodule Broom.Behaviour do
  alias Broom.BaseTypes, as: Types
  alias Broom.TrackerEntry

  @type broom_child_spec_opts() :: map() | keyword()

  @callback child_spec(broom_child_spec_opts()) :: Supervisor.child_spec()
  @callback track_timeout(TrackerEntry.t()) :: Types.db_result()
end
