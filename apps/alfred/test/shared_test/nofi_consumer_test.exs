defmodule Alfred.NofiConsumerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_nofi_consumer: true

  describe "Alfred.NofiConsumer" do
    test "starts, provides info and can trigger a notify" do
      assert {:ok, server_pid} = Alfred.NofiConsumer.start_link(interval_ms: :all)

      info = Alfred.NofiConsumer.info(server_pid)

      test_pid = self()

      assert %{
               name: <<_::binary>> = name,
               caller_pid: ^test_pid,
               server_pid: ^server_pid,
               name_pid: name_pid,
               ticket: %Alfred.Ticket{} = ticket,
               seen_at: :never
             } = info

      assert Process.alive?(name_pid)

      assert :ok = Alfred.NofiConsumer.trigger(server_pid)

      assert_receive({%Alfred.Memo{name: ^name}, %{ticket: ^ticket}}, 1)
    end
  end
end
