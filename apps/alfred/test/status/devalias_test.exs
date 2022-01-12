defmodule Alfred.DevAliasTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_dev_alias: true

  describe "Alfred.Test.DevAlias.new/1" do
    test "creates mutable from parts" do
      parts = %{type: :mut, cmd: "on", rc: :expired, expired_ms: 15000, name: "some name"}

      assert %Alfred.Test.DevAlias{
               cmds: [
                 %Alfred.Test.Command{
                   acked: true,
                   acked_at: %DateTime{},
                   cmd: "on",
                   orphaned: false,
                   refid: <<_::binary>>,
                   rt_latency_us: 20,
                   sent_at: %DateTime{}
                 }
               ],
               datapoints: nil,
               description: "equipment",
               device: [],
               inserted_at: %DateTime{},
               name: "some name",
               pio: 0,
               ttl_ms: 15_000,
               updated_at: %DateTime{}
             } = Alfred.Test.DevAlias.new(parts)
    end
  end
end
