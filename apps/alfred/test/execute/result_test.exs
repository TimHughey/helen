defmodule Alfred.ExecResultTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_exec_result: true

  alias Alfred.ExecResult
  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  describe "Alfred.ExecResult.to_binary/2" do
    @tag name_add: [type: :mut]
    test "creates OK binary", ctx do
      %ExecResult{name: ctx.name, rc: :ok, cmd: "on"}
      |> ExecResult.to_binary()
      |> Should.Contain.binaries(["OK", ctx.name, "on"])
    end

    @tag name_add: [type: :mut]
    test "creates PENDING binary", ctx do
      %ExecResult{name: ctx.name, rc: :pending, cmd: "on", refid: "87aedf"}
      |> ExecResult.to_binary()
      |> Should.Contain.binaries(["PENDING", ctx.name, "on", "@87aedf"])
    end

    @tag name_add: [type: :mut]
    test "creates NOT_FOUND binary", ctx do
      %ExecResult{name: ctx.name, rc: :not_found, cmd: "on"}
      |> ExecResult.to_binary()
      |> Should.Contain.binaries(["NOT_FOUND", ctx.name])
    end

    @tag name_add: [type: :mut]
    test "creates TTL_EXPIRED binary", ctx do
      %ExecResult{name: ctx.name, rc: {:ttl_expired, 49_152}, cmd: "on"}
      |> ExecResult.to_binary()
      |> Should.Contain.binaries(["TTL_EXPIRED", ctx.name, "+49152"])
    end

    @tag name_add: [type: :mut]
    test "creates INVALID binary", ctx do
      %ExecResult{name: ctx.name, rc: :invalid, cmd: "on"}
      |> ExecResult.to_binary()
      |> Should.Contain.binaries(["INVALID", ctx.name])
    end
  end
end
