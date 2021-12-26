defmodule Carol.InstanceTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_instance: true

  alias Carol.Instance

  describe "Carol.Instance.id/1" do
    test "reates proper id" do
      Instance.id({CarolTest, :greenhouse})
      |> Should.Be.module()
    end
  end

  describe "Carol.Instance.module/1" do
    test "creates proper module" do
      Instance.module({CarolTest, :greenhouse}) |> Should.Be.module()
    end
  end

  describe "Carol.Instance.start_args/1" do
    test "returns args for an instance" do
      want_keys = [:id, :opts, :defaults, :equipment, :episodes]

      Instance.start_args({:carol, CarolTest, :front_chandelier})
      |> Should.Be.List.with_keys(want_keys)
    end
  end

  describe "Carol.Instance.display_name/1" do
    test "parses module name into humanized" do
      Instance.id({CarolTest, :front_chandelier})
      |> Instance.display_name()
      |> Should.Be.binary()
    end
  end
end
