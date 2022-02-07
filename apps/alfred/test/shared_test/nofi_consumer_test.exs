defmodule Alfred.NofiConsumerTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_nofi_consumer: true

  setup [:nofi_add]

  describe "Alfred.NofiConsumer" do
    @tag nofi_add: [interval_ms: :all]
    test "starts, provides info and can trigger a notify", ctx do
      assert %{nofi_server: {:ok, server_pid}} = ctx

      info = Alfred.NofiConsumer.info(server_pid)

      test_pid = self()

      assert %{
               name: <<_::binary>> = name,
               dev_alias: %{register: name_pid},
               caller_pid: ^test_pid,
               server_pid: ^server_pid,
               ticket: %Alfred.Ticket{} = ticket,
               seen_at: :never
             } = info

      assert Process.alive?(name_pid)

      assert :ok = Alfred.NofiConsumer.trigger(server_pid)

      assert_receive({%Alfred.Memo{name: ^name}, %{ticket: ^ticket}}, 1)
    end
  end
end
