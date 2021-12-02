defmodule Alfred.StatusProtocolTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_status_protocol: true

  alias Alfred.Status

  alias Alfred.ImmutableStatus, as: ImmStatus

  describe "Alfred.ImmStatusSrc.new/1" do
    alias Alfred.Test.DevAlias, as: DevAlias

    @tag device: [], datapoints: []
    test "creates a well formed default DevAlias", ctx do
      ctx |> DevAlias.new() |> Should.Be.struct(Alfred.Test.DevAlias)
      # |> pretty_puts()
    end
  end

  describe "Alfred.Status.create/2" do
    @tag skip: true
    test "handles a not found" do
      Status.not_found({:not_found, "foobar"}, ImmStatus, []) |> pretty_puts()
    end
  end
end
