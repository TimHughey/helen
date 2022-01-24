# defmodule Sally.DispatchTest do
#   @moduledoc false
#
#   use ExUnit.Case, async: true
#   use Sally.TestAid
#
#   @moduletag sally: true, sally_dispatch: true
#
#   describe "Sally.Dispatch.accept/1" do
#     @tag dispatch_aid: [subsystem: "host", category: "boot"]
#     test "handles a boot message", ctx
# 
