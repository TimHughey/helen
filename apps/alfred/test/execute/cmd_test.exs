defmodule Alfred.ExecCmdTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_exec_cmd: true

  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  describe "Alfred.ExecCmd.new/2" do
    @tag name_add: [type: :mut]
    test "creates an ExecCmd from a list of opts", %{name: name} do
      assert %Alfred.ExecCmd{name: ^name, cmd: "special", cmd_params: %{type: "fixed", percent: 25}} =
               Alfred.ExecCmd.new(name: name, cmd: "special", cmd_params: [type: "fixed", percent: 25])
    end

    @tag name_add: [type: :mut, cmd: "on"]
    test "create a name", %{name: name} do
      assert name =~ ~r/^mutable_[a-f0-9]{12}\sok\son$/
    end
  end

  describe "Alfred.ExecCmd.params_adjust/2" do
    test "handles cmd name without version number" do
      assert %Alfred.ExecCmd{cmd: "fade dim v001", cmd_params: %{type: "random", min: 1, max: 128}} =
               Alfred.ExecCmd.new(
                 name: "foo",
                 cmd: "fade dim",
                 cmd_params: [type: "random", min: 0, max: 128]
               )
               |> Alfred.ExecCmd.validate()
               |> Alfred.ExecCmd.params_adjust(min: 1)
    end

    test "handles cmd name with version number" do
      assert %Alfred.ExecCmd{cmd: "fade dim v002", cmd_params: %{type: "random", min: 1, max: 128}} =
               Alfred.ExecCmd.new(
                 name: "foo",
                 cmd: "fade dim v001",
                 cmd_params: [type: "random", min: 0, max: 128]
               )
               |> Alfred.ExecCmd.validate()
               |> Alfred.ExecCmd.params_adjust(min: 1)
    end
  end

  describe "Aflred.ExecCmd.Args.auto/2" do
    test "creates args from :id, :equipment, :params, :opts (no defaults)" do
      assert [
               cmd: "Overnight",
               cmd_opts: [ack: :immediate],
               cmd_params: [max: 256, min: 0, type: "random"],
               name: "equip name",
               pub_opts: []
             ] =
               Alfred.ExecCmd.Args.auto(
                 [
                   id: "Overnight",
                   params: [type: "random", min: 0, max: 256],
                   equipment: "equip name",
                   opts: [ack: :immediate]
                 ],
                 []
               )
    end

    test "creates args from cmd: :off, :name (no defaults)" do
      assert [cmd: "off", cmd_opts: [], cmd_params: [], name: "some name", pub_opts: []] =
               Alfred.ExecCmd.Args.auto([cmd: "off", name: "some name"], [])
    end

    test "honors defaults" do
      assert [
               cmd: "special",
               cmd_opts: [ack: :immediate],
               cmd_params: [max: 256, min: 0, type: "random"],
               name: "some name",
               pub_opts: []
             ] =
               Alfred.ExecCmd.Args.auto(
                 [
                   cmd: "special",
                   cmd_opts: [ack: :immediate],
                   cmd_params: [min: 0, type: "random"],
                   name: "some name"
                 ],
                 params: [max: 256]
               )
    end

    test "honors short cmd opts keys" do
      assert [
               cmd: "on",
               cmd_opts: [ack: :immediate, notify_when_released: true],
               cmd_params: [],
               name: "some name",
               pub_opts: []
             ] =
               Alfred.ExecCmd.Args.auto([cmd: :on], name: "some name", notify: true, opts: [ack: :immediate])
    end

    test "keeps original arg when defaults contains cmd" do
      assert [
               cmd: "special",
               cmd_opts: [ack: :immediate],
               cmd_params: [type: "random"],
               name: "some name",
               pub_opts: []
             ] =
               Alfred.ExecCmd.Args.auto([cmd: "special", name: "some name", params: [type: "random"]],
                 cmd: :on,
                 opts: [ack: :immediate]
               )
    end

    test "ignores unknown args" do
      args = Alfred.ExecCmd.Args.auto({[cmd: :on, weird_opt: true, name: "some name", notify: true], []})

      refute Enum.any?(args, fn kv -> kv == {:weird_opt, true} end)
    end
  end

  describe "Alfred.ExecCmd.version_cmd/1" do
    test "handles args list with unversioned cmd" do
      "special v001" = Alfred.ExecCmd.version_cmd("special")
    end

    test "handles args list with versioned cmd" do
      assert [{:cmd, "special v002"} | _] = Alfred.ExecCmd.version_cmd(cmd: "special v001")
    end

    test "handles args list with atom and binary cmd" do
      assert [cmd: :off] = Alfred.ExecCmd.version_cmd(cmd: :off)
      assert [cmd: "off"] = Alfred.ExecCmd.version_cmd(cmd: "off")
      assert [cmd: "on"] = Alfred.ExecCmd.version_cmd(cmd: "on")
      assert [cmd: :on] = Alfred.ExecCmd.version_cmd(cmd: :on)
    end

    test "handles args list without cmd" do
      assert [{:name, "name"} | _] = Alfred.ExecCmd.version_cmd(name: "name")
    end

    test "handles binary cmd" do
      assert "special v001" = Alfred.ExecCmd.version_cmd("special")
    end
  end
end
