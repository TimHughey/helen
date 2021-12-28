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

  describe "Alfred.ExecCmd.Args.auto/1" do
    test "creates args from :id, :equipment, :params, :opts" do
      params = [type: "random", min: 0, max: 256]
      opts = [ack: :immediate]

      base = [cmd: "Overnight", name: "equip name"]
      cmd_params = [cmd_params: [max: 256, min: 0, type: "random"]]
      cmd_opts = [cmd_opts: [ack: :immediate]]
      want_kv = base ++ cmd_params ++ cmd_opts

      [id: "Overnight", params: params, equipment: "equip name", opts: opts]
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Be.List.with_all_key_value(want_kv)
    end

    test "creates args from cmd: :off, :name" do
      [cmd: :off, name: "equip name"]
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Be.List.with_all_key_value(cmd: "off", name: "equip name")
    end

    test "honors defaults" do
      defaults = [opts: [ack: :immediate], params: [min: 0]]
      want_opts = [ack: :immediate]
      want_params = [min: 0, type: "random"]
      want_kv = [cmd: "special", cmd_opts: want_opts, cmd_params: want_params, name: "equip name"]

      [cmd: "special", defaults: defaults, name: "equip name", params: [type: "random"]]
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Be.List.with_all_key_value(want_kv)
    end

    test "prunes spurious args" do
      defaults = [opts: [ack: :immediate], params: [min: 0]]
      want_match = [cmd: "on", cmd_opts: [ack: :immediate], name: "equip name"]

      [cmd: "on", defaults: defaults, name: "equip name", params: [type: "random"]]
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Be.match(want_match)
    end

    test "keeps original arg when defaults contains cmd" do
      defaults = [cmd: "off", opts: [ack: :immediate], params: [min: 0]]
      want_opts = [ack: :immediate]
      want_params = [min: 0, type: "random"]
      want_kv = [cmd: "special", cmd_opts: want_opts, cmd_params: want_params, name: "equip name"]

      [cmd: "special", defaults: defaults, name: "equip name", params: [type: "random"]]
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Be.List.with_all_key_value(want_kv)
    end
  end

  describe "Aflred.ExecCmd.Args.auto/2" do
    test "creates args from :id, :equipment, :params, :opts (no defaults)" do
      params = [type: "random", min: 0, max: 256]
      opts = [ack: :immediate]

      base = [cmd: "Overnight", name: "equip name"]
      cmd_params = [cmd_params: [max: 256, min: 0, type: "random"]]
      cmd_opts = [cmd_opts: [ack: :immediate]]
      want_kv = base ++ cmd_params ++ cmd_opts

      [id: "Overnight", params: params, equipment: "equip name", opts: opts]
      |> Alfred.ExecCmd.Args.auto([])
      |> Should.Contain.kv_pairs(want_kv)
    end

    test "creates args from cmd: :off, :name (no defaults)" do
      [cmd: :off, name: "equip name"]
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Contain.kv_pairs(cmd: "off", name: "equip name")
    end

    test "honors defaults" do
      defaults = [opts: [ack: :immediate], params: [min: 0]]

      want_opts = [ack: :immediate]
      want_params = [min: 0, type: "random"]
      want_kv = [cmd: "special", cmd_opts: want_opts, cmd_params: want_params, name: "equip name"]

      [cmd: "special", name: "equip name", params: [type: "random"]]
      |> Alfred.ExecCmd.Args.auto(defaults)
      |> Should.Contain.kv_pairs(want_kv)
    end

    test "honors short cmd opts keys" do
      defaults = [ack: :immediate]

      want_opts = [ack: :immediate, notify_when_released: true]
      want_kv = [cmd: "on", name: "some name", cmd_opts: want_opts]

      [cmd: :on, name: "some name", notify: true]
      |> Alfred.ExecCmd.Args.auto(defaults)
      |> Should.Contain.kv_pairs(want_kv)
    end

    test "keeps original arg when defaults contains cmd" do
      defaults = [cmd: "off", opts: [ack: :immediate], params: [min: 0]]

      want_opts = [ack: :immediate]
      want_params = [min: 0, type: "random"]
      want_kv = [cmd: "special", cmd_opts: want_opts, cmd_params: want_params, name: "equip name"]

      [cmd: "special", name: "equip name", params: [type: "random"]]
      |> Alfred.ExecCmd.Args.auto(defaults)
      |> Should.Contain.kv_pairs(want_kv)
    end

    test "ignores unknown args" do
      defaults = [ack: :immediate]

      want_opts = [ack: :immediate, notify_when_released: true]
      want_kv = [cmd: "on", name: "some name", cmd_opts: want_opts]

      {[cmd: :on, weird_opt: true, name: "some name", notify: true], defaults}
      |> Alfred.ExecCmd.Args.auto()
      |> Should.Contain.kv_pairs(want_kv)
      |> then(fn args -> refute args[:weird_opt], Should.msg(args, "should include :weird_opt") end)
    end
  end

  describe "Alfred.ExecCmd.version_cmd/1" do
    test "handles args list with unversioned cmd" do
      [cmd: "special"]
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.List.with_all_key_value(cmd: "special v001")
    end

    test "handles args list with versioned cmd" do
      [cmd: "special v001"]
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.List.with_all_key_value(cmd: "special v002")
    end

    test "handles args list with atom cmd" do
      [cmd: :off]
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.List.with_all_key_value(cmd: :off)
    end

    test "handles args list with 'off' cmd" do
      [cmd: "off"]
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.List.with_all_key_value(cmd: "off")
    end

    test "handles args list without cmd" do
      [name: "name"]
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.List.with_all_key_value(name: "name")
    end

    test "handles binary cmd" do
      "special"
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.equal("special v001")
    end

    test "handles atom cmd" do
      :on
      |> Alfred.ExecCmd.version_cmd()
      |> Should.Be.equal(:on)
    end
  end
end
