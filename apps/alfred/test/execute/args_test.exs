defmodule Alfred.ExecuteArgsTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_execute_args: true

  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  describe "Alfred.Execute.Args.auto/2" do
    test "creates args from :id, :equipment, :params, :opts (no defaults)" do
      want_params = [type: "random", min: 0, max: 256]
      want_opts = [ack: :immediate]
      base = [id: "Overnight", params: want_params, equipment: "equip name", opts: want_opts]
      args = Alfred.Execute.Args.auto(base, [])

      assert [cmd: "Overnight", cmd_opts: got_opts, cmd_params: got_params, name: "equip name"] = args

      assert Enum.sort(want_params) == Enum.sort(got_params)
      assert Enum.sort(want_opts) == Enum.sort(got_opts)
    end

    test "creates args from cmd: :off, :name (no defaults)" do
      args = Alfred.Execute.Args.auto([cmd: "off", name: "some name"], [])
      assert [cmd: "off", cmd_opts: [], cmd_params: [], name: "some name"] = args
    end

    test "honors defaults" do
      assert [
               cmd: "special",
               cmd_opts: [ack: :immediate],
               cmd_params: [max: 256, min: 0, type: "random"],
               name: "some name"
             ] =
               Alfred.Execute.Args.auto(
                 [
                   cmd_opts: [ack: :immediate],
                   cmd_params: [min: 0, type: "random"],
                   name: "some name"
                 ],
                 cmd: "special",
                 params: [max: 256]
               )
    end

    test "honors only defaults" do
      assert [
               cmd: "special",
               cmd_opts: [ack: :immediate],
               cmd_params: [max: 256, min: 0, type: "random"],
               name: "some name"
             ] =
               Alfred.Execute.Args.auto(
                 [],
                 name: "some name",
                 cmd: "special",
                 opts: [ack: :immediate],
                 params: [max: 256, min: 0, type: "random"]
               )
    end

    test "ignores :id when :cmd present in defaults" do
      assert [
               cmd: "25% of max",
               cmd_opts: [],
               cmd_params: [percent: 25, type: "fixed"],
               name: "some name"
             ] =
               Alfred.Execute.Args.auto(
                 [id: "ignore this", name: "some name", params: [percent: 25, type: "fixed"]],
                 cmd: "25% of max"
               )
    end

    test "honors short cmd opts keys" do
      assert [
               cmd: "on",
               cmd_opts: [ack: :immediate, notify_when_released: true],
               cmd_params: [],
               name: "some name"
             ] =
               Alfred.Execute.Args.auto([cmd: :on], name: "some name", notify: true, opts: [ack: :immediate])
    end

    test "keeps original arg when defaults contains cmd" do
      assert [
               cmd: "special",
               cmd_opts: [ack: :immediate],
               cmd_params: [type: "random"],
               name: "some name"
             ] =
               Alfred.Execute.Args.auto([cmd: "special", name: "some name", params: [type: "random"]],
                 cmd: :on,
                 opts: [ack: :immediate]
               )
    end

    test "ignores unknown args" do
      args = Alfred.Execute.Args.auto({[cmd: :on, weird_opt: true, name: "some name", notify: true], []})

      refute Enum.any?(args, fn kv -> kv == {:weird_opt, true} end)
    end
  end

  describe "Alfred.Execute.Args.version_cmd/1" do
    test "handles args list with unversioned cmd" do
      "special v001" = Alfred.Execute.Args.version_cmd("special")
    end

    test "handles args list with versioned cmd" do
      assert [{:cmd, "special v002"} | _] = Alfred.Execute.Args.version_cmd(cmd: "special v001")
    end

    test "handles args list with versioned cmd (special characters)" do
      assert [{:cmd, "25% of max v002"} | _] = Alfred.Execute.Args.version_cmd(cmd: "25% of max v001")
    end

    test "handles args list with atom and binary cmd" do
      assert [cmd: :off] = Alfred.Execute.Args.version_cmd(cmd: :off)
      assert [cmd: "off"] = Alfred.Execute.Args.version_cmd(cmd: "off")
      assert [cmd: "on"] = Alfred.Execute.Args.version_cmd(cmd: "on")
      assert [cmd: :on] = Alfred.Execute.Args.version_cmd(cmd: :on)
    end

    test "handles args list without cmd" do
      assert [{:name, "name"} | _] = Alfred.Execute.Args.version_cmd(name: "name")
    end

    test "handles binary cmd" do
      assert "special v001" = Alfred.Execute.Args.version_cmd("special")
    end
  end
end
