defmodule Alfred.UseTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_client: true

  setup [:name_add]

  describe "Alfred.__using__/1" do
    test "uses Alfred.Name when execute or status features present in use_opts" do
      attributes = Alfred.Test.Client.__info__(:attributes)

      attribute_count = Enum.count(attributes, fn {key, _val} -> to_string(key) =~ "alfred" end)

      assert attribute_count == 3
    end
  end

  describe "Alfred.Client" do
    @tag name_add: [prefix: "server"]
    test "responds to :status_lookup messages", ctx do
      assert %{name: name} = ctx

      assert {:ok, pid} = start_supervised({Alfred.Test.Client, name})
      assert is_pid(pid)

      assert ^name = Alfred.Test.Client.name(pid)

      status = Alfred.status(name)
      assert %Alfred.Status{name: ^name, story: story, rc: :ok} = status
      assert %{hello: :doctor} = story
    end

    @tag name_add: [prefix: "server"]
    test "responds to :execute_cmd messages", ctx do
      assert %{name: name} = ctx

      assert {:ok, pid} = start_supervised({Alfred.Test.Client, name})
      assert is_pid(pid)

      assert ^name = Alfred.Test.Client.name(pid)

      cmd = "state"
      execute = Alfred.execute(name: name, cmd: cmd)
      assert %Alfred.Execute{name: ^name, cmd: ^cmd, story: story, rc: :ok} = execute
      assert %{name: <<_::binary>>, cmd: ^cmd, nature: :server} = story
    end
  end
end
