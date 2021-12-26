# defmodule Glow.InstanceTest do
#   use ExUnit.Case, async: true
#   use Should
#
#   @moduletag glow: true, glow_instance: true
#
#   alias Glow.Instance
#
#   describe "Glow.Instance.id/1" do
#     test "reates proper id" do
#       Instance.id(:greenhouse) |> Should.Be.module()
#     end
#   end
#
#   describe "Glow.Instance.module/1" do
#     test "creates proper module" do
#       Instance.module(:greenhouse) |> Should.Be.module()
#     end
#   end
#
#   describe "Glow.Instance.start_args/1" do
#     test "returns args for an instance" do
#       require Glow.Instance
#
#       Instance.start_args(:front_chandelier)
#       |> Should.Be.List.with_all_key_value(id: Glow.FrontChandelier)
#     end
#   end
#
#   describe "Glow.Instance.display_name/1" do
#     test "parses module name into humanized" do
#       Instance.id(:front_chandelier) |> Instance.display_name()
#     end
#   end
# end
