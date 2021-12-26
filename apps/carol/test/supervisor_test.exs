defmodule UseCarol.Gamma do
  use Carol, otp_app: :carol
end

defmodule CarolSupervisorTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_supervisor: true
end
