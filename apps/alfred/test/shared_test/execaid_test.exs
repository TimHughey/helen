defmodule Alfred.ExecAidTest do
  use ExUnit.Case, async: true

  @moduletag alfed: true, alfred_exec_aid: true

  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  describe "Alfred.ExecAid.execute/2" do
    @tag name_add: [type: :mut]
    test "accepts a list of cmd opts and creates an ExecCmd", %{name: name} do
      assert %Alfred.ExecCmd{name: ^name} =
               Alfred.ExecCmd.new(name: name, cmd: "special", cmd_params: [type: "fixed", percent: 25])
    end
  end
end
