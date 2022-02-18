defmodule CarolServerTest do
  use ExUnit.Case
  use Alfred.TestAid
  use Carol.TestAid
  use Should

  @moduletag carol: true, carol_server: true

  setup [:episodes_add, :start_args_add, :init_add]

  describe "Carol.Server starts supervised" do
    @tag start_args_add: {:app, :carol, Carol.NoEpisodes, :first_instance}
    test "with empty config", %{child_spec: child_spec, server_name: server_name} do
      assert {:ok, pid} = start_supervised(child_spec)

      assert state = :sys.get_state(pid)
      assert %Carol.State{} = state
      assert %{episodes: [], equipment: equipment, server_name: ^server_name} = state
      assert equipment =~ ~r/first/
    end

    @tag start_args_add: {:app, :carol, Carol.Test, :front_chandelier}
    test "with epsiodes", %{child_spec: child_spec, server_name: server_name} do
      assert {:ok, pid} = start_supervised(child_spec)
      state = :sys.get_state(pid)

      assert %Carol.State{server_name: ^server_name, ticket: {:ok, _}} = state
      assert %{seen_at: :none} = state
      assert %{episodes: episodes} = state

      assert Enum.count(episodes) == 3
      assert Enum.all?(episodes, &match?(%Carol.Episode{}, &1))
    end
  end

  describe "Carol.Server starts unsupervised" do
    @tag init_add: [episodes: {:short, [future: 12, now: 1, past: 1]}]
    test "with init args", ctx do
      assert %{init_args: init_args} = ctx

      assert {:ok, pid} = GenServer.start_link(Carol.Server, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
    end
  end

  describe "Carol.Server runs" do
    @tag init_add: [episodes: {:short, [future: 12, now: 1, past: 1]}]
    test "live plus multiple short episodes", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias} = ctx
      assert %{name: <<_::binary>>} = dev_alias

      server_name = get_in(init_args, [:instance])
      assert <<_::binary>> = server_name

      # start the server
      assert {:ok, pid} = GenServer.start_link(Carol.Server, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)

      # NOTE: first noreply from bootstrap
      assert_receive({:noreply, %Carol.State{tick: nil}}, 2000)

      # NOTE: call register/1 on the equipment to trigger a notify which, in turn,
      # triggers the server to register itself
      Alfred.DevAlias.register(dev_alias)

      assert_receive({:noreply, state}, 2000)
      assert %Carol.State{episodes: episodes, tick: tick} = state
      assert [%{id: "Now 1"} | episodes_rest] = episodes
      assert is_reference(tick)

      want_ids = Enum.map(episodes_rest, &Map.get(&1, :id))

      Enum.reduce(want_ids, [], fn
        # NOTE: skip Past ids they won't be avtive for hours
        <<"Past"::binary, _::binary>> = want_id, unseen_ids ->
          [want_id | unseen_ids]

        <<_::binary>> = want_id, acc ->
          assert_receive({:noreply, state}, 5000)
          assert %Carol.State{tick: tick} = state

          assert %{story: %{active_id: ^want_id}} = Alfred.status(server_name)

          timer_ms = Process.read_timer(tick)
          assert is_integer(timer_ms)
          assert timer_ms > 100

          acc
      end)
      |> Enum.each(fn id -> assert id =~ ~r/Past/ end)
    end
  end
end
