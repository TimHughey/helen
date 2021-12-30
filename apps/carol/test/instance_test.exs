defmodule Carol.InstanceTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_instance: true

  alias Carol.Instance

  describe "Carol.Instance.id/1" do
    test "reates proper id" do
      assert CarolTest.Greenhouse = Instance.module({CarolTest, :greenhouse})
    end
  end

  describe "Carol.Instance.module/1" do
    test "creates proper module" do
      assert CarolTest.Greenhouse = Instance.module({CarolTest, :greenhouse})
    end
  end

  describe "Carol.Instance.start_args/1" do
    test "returns args for an instance" do
      assert [
               id: CarolTest.FrontChandelier,
               instance: :front_chandelier,
               opts: _,
               defaults: _,
               equipment: _,
               episodes: [_ | _]
             ] = Instance.start_args({:carol, CarolTest, :front_chandelier})
    end
  end

  describe "Carol.Instance.display_name/1" do
    test "parses module name into humanized" do
      assert "Front Chandelier" = Instance.id({CarolTest, :front_chandelier}) |> Instance.display_name()
    end
  end
end
