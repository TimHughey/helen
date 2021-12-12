defmodule Glow.InstanceTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag glow: true, glow_instance: true

  alias Glow.Instance

  describe "Glow.Instance" do
    test "id/1 creates proper id" do
      Instance.id(:greenhouse) |> Should.Be.module()
    end

    test "module/1 creates proper module" do
      Instance.module(:greenhouse) |> Should.Be.module()
    end

    test "start_args/1 returns args for an instance" do
      require Glow.Instance

      Instance.start_args(:front_chandelier)
      |> Should.Be.List.with_all_key_value(id: Glow.FrontChandelier)
    end
  end
end
