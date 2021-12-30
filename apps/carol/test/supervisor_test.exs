defmodule UseCarol.Gamma do
  use Carol, otp_app: :carol
end

defmodule CarolSupervisorTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_supervisor: true
end
