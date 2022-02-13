defmodule Carol.InstanceTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_instance: true

  alias Carol.Instance

  describe "Carol.Instance.id/1" do
    test "reates proper id" do
      assert Carol.Greenhouse = Instance.module({Carol.Test, :greenhouse})
    end
  end

  describe "Carol.Instance.module/1" do
    test "creates proper module" do
      assert Carol.Greenhouse = Instance.module({Carol.Test, :greenhouse})
    end
  end

  describe "Carol.Instance.start_args/1" do
    test "returns args for an instance" do
      assert [
               id: Carol.FrontChandelier,
               instance: :front_chandelier,
               opts: _,
               defaults: _,
               equipment: _,
               episodes: [_ | _]
             ] = Instance.start_args({:carol, Carol.Test, :front_chandelier})
    end
  end

  describe "Carol.Instance.display_name/1" do
    test "parses module name into humanized" do
      assert "Front Chandelier" = Instance.id({Carol.Test, :front_chandelier}) |> Instance.display_name()
    end
  end
end
