defmodule Alfred.ExecCmdTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_exec_cmd: true

  alias Alfred.ExecCmd
  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  describe "Alfred.ExecCmd.new/2" do
    @tag name_add: [type: :mut]
    test "creates an ExecCmd from a list of opts", ctx do
      [name: ctx.name, cmd: "special", cmd_params: [type: "fixed", percent: 25]]
      |> ExecCmd.new()
      |> Should.Be.struct(ExecCmd)
    end

    @tag name_add: [type: :mut, cmd: "on"]
    test "create a name", ctx do
      ctx.name |> Should.Be.binary()
    end
  end

  describe "Alfred.ExecCmd.params_adjust/2" do
    test "handles cmd name without version number" do
      [name: "foo", cmd: "fade dim", cmd_params: [type: "random", min: 0, max: 128]]
      |> ExecCmd.new()
      |> ExecCmd.validate()
      |> ExecCmd.params_adjust(min: 1)
      |> tap(fn ec -> Should.Be.Struct.with_all_key_value(ec, ExecCmd, cmd: "fade dim v001") end)
      |> Should.Be.Struct.with_key(ExecCmd, :cmd_params)
      |> Should.Contain.kv_pairs(min: 1, max: 128, type: "random")
    end

    test "handles cmd name with version number" do
      [name: "foo", cmd: "fade dim v001", cmd_params: [type: "random", min: 0, max: 128]]
      |> ExecCmd.new()
      |> ExecCmd.validate()
      |> ExecCmd.params_adjust(min: 1)
      |> tap(fn ec -> Should.Be.Struct.with_all_key_value(ec, ExecCmd, cmd: "fade dim v002") end)
      |> Should.Be.Struct.with_key(ExecCmd, :cmd_params)
      |> Should.Contain.kv_pairs(min: 1, max: 128, type: "random")
    end
  end
end
