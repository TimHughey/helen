defmodule Alfred.StatusProtocolTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_status_protocol: true

  describe "Alfred.ImmStatusSrc.new/1" do
    @tag device: [], datapoints: []
    test "creates a well formed default DevAlias", ctx do
      dev_alias = Alfred.Test.DevAlias.new(ctx)
      assert %Alfred.Test.DevAlias{} = dev_alias
    end
  end

  describe "Alfred.Status.create/2" do
    test "handles a not found" do
      assert %Alfred.ImmutableStatus{} =
               Alfred.Status.not_found({:not_found, "foobar"}, Alfred.ImmutableStatus, [])
    end
  end
end
