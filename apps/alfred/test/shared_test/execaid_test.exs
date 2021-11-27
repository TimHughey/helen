defmodule Alfred.ExecAidTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfed: true, alfred_exec_aid: true

  alias Alfred.ExecCmd
  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  describe "Alfred.ExecAid.execute/2" do
    @tag name_add: [type: :mut]
    test "accepts a list of cmd opts and creates an ExecCmd", ctx do
      [name: ctx.name, cmd: "special", cmd_params: [type: "fixed", percent: 25]]
      |> ExecCmd.new()
      |> Should.Be.struct(ExecCmd)
    end
  end
end
