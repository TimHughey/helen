defmodule Alfred.NofiConsumerTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_nofi_consumer: true

  describe "Alfred.NofiConsumer" do
    test "starts, provides info and can trigger a notify" do
      args = [interval_ms: :all]
      assert {:ok, server_pid} = Alfred.NofiConsumer.start_link(args)

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
