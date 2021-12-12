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
end
