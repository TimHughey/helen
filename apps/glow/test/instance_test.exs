defmodule Glow.InstanceTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag glow: true, glow_instance: true

  alias Glow.Instance

  test "Glow.Instance.id/1" do
    Instance.id(:greenhouse) |> Should.Be.module()
  end
end
