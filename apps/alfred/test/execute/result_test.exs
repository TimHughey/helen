defmodule Alfred.ExecResultTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_exec_result: true

  import Alfred.NamesAid, only: [name_add: 1]

  setup [:name_add]

  @name_re "[a-z]+_[a-f0-9]{12} .*"
  defmacro assert_to_binary(parts) do
    quote location: :keep, bind_quoted: [parts: parts] do
      parts = Enum.into(parts, %{})
      er = struct(Alfred.ExecResult, parts)

      assert %Alfred.ExecResult{name: name} = er

      x = Alfred.ExecResult.to_binary(er)

      case parts do
        %{cmd: cmd, rc: :ok} ->
          assert x =~ ~r/^OK \{#{cmd}\} \[#{@name_re}\]$/

        %{cmd: cmd, rc: :pending, refid: refid} ->
          assert x =~ ~r/^PENDING \{#{cmd}\} @#{refid} \[#{@name_re}\]$/

        %{rc: :not_found} ->
          assert x =~ ~r/^NOT_FOUND \[#{@name_re}\]$/

        %{rc: {:ttl_expired, ms}} ->
          assert x =~ ~r/TTL_EXPIRED \+#{ms}ms \[#{@name_re}\]$/

        %{rc: :invalid} ->
          assert x =~ ~r/INVALID \[#{@name_re}\]$/
      end
    end
  end

  describe "Alfred.ExecResult.to_binary/2" do
    @tag name_add: [type: :mut]
    test "creates OK binary", ctx do
      parts = [name: ctx.name, rc: :ok, cmd: "on"]

      assert_to_binary(parts)
    end

    @tag name_add: [type: :mut]
    test "creates PENDING binary", ctx do
      parts = [name: ctx.name, rc: :pending, cmd: "on", refid: "87aedf"]

      assert_to_binary(parts)
    end

    @tag name_add: [type: :mut]
    test "creates NOT_FOUND binary", ctx do
      parts = [name: ctx.name, rc: :not_found, cmd: "on"]

      assert_to_binary(parts)
    end

    @tag name_add: [type: :mut]
    test "creates TTL_EXPIRED binary", ctx do
      parts = [name: ctx.name, rc: {:ttl_expired, 49_152}, cmd: "on"]

      assert_to_binary(parts)
    end

    @tag name_add: [type: :mut]
    test "creates INVALID binary", ctx do
      parts = [name: ctx.name, rc: :invalid, cmd: "on"]

      assert_to_binary(parts)
    end
  end

  describe "Alfred.ExecResult.log_failure_if_needed/2" do
    test "handles an ExecResult with :rc in [:ok, :pending]" do
      er = %Alfred.ExecResult{name: "foo", rc: :ok, cmd: "on"}

      assert ^er = Alfred.ExecResult.log_failure_if_needed(er, module: __MODULE__)
    end

    test "handles an ExecResult with ttl_expired" do
      er = %Alfred.ExecResult{name: "foo", rc: {:ttl_expired, 49_152}, cmd: "on"}

      assert ^er = Alfred.ExecResult.log_failure_if_needed(er, module: __MODULE__)
    end

    test "handles an ExecResult with rc: :not_found" do
      er = %Alfred.ExecResult{name: "foo", rc: :not_found}

      assert ^er = Alfred.ExecResult.log_failure_if_needed(er, module: __MODULE__)
    end
  end
end
