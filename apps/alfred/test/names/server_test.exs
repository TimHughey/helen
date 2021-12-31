defmodule Alfred.NamesServerTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_names_server: true

  setup_all do
    assert {:ok, pid} = start_supervised({Alfred.Names.Server, [names_server: __MODULE__]})
    assert is_pid(pid)

    call_opts = [names_server: __MODULE__]

    %{pid: pid, server_name: __MODULE__, call_opts: call_opts, state: %Alfred.Names.State{}}
  end

  setup [:known_name_add, :known_names_add, :handle_add]

  describe "Alfred.Names.Server starts" do
    test "via applicaton" do
      pid = GenServer.whereis(Alfred.Names.Server)
      assert is_pid(pid)
    end

    test "with specified name", %{server_name: server_name} do
      pid = GenServer.whereis(server_name)
      assert is_pid(pid)
    end
  end

  describe "Alfred.Names.Server.call" do
    test "handles when a server is not available" do
      assert {:no_server, Foo.Bar} = Alfred.Names.Server.call({:foo}, names_server: Foo.Bar)
    end

    test "handles when the server is available", ctx do
      known_names = Alfred.Names.Server.call(:known, ctx.call_opts)
      assert is_list(known_names)
    end
  end

  describe "Alfred.Names.Server.handle_call({:just_saw})" do
    @tag known_name_add: []
    test "processes an empty list", ctx do
      assert {:reply, [], %Alfred.Names.State{}} =
               Alfred.Names.Server.handle_call({:just_saw, []}, nil, ctx.state)
    end

    @tag known_names_add: [], handle_add: :just_saw
    test "processes a KnownName list", ctx do
      assert is_list(ctx.handle_result)
    end
  end

  describe "Alfred.Names.Server.handle_call({:delete})" do
    @tag known_name_add: [], handle_add: :just_saw
    test "deletes a name", %{known_name: %{name: name}, new_state: new_state} do
      # delete a known name, returns deleted name
      assert {:reply, ^name, %Alfred.Names.State{known: %{}}} =
               Alfred.Names.Server.handle_call({:delete, name}, nil, new_state)
    end

    @tag known_name_add: [], handle_add: :just_saw
    test "handles when a name does not exist", %{new_state: new_state} do
      # attempt to delete an unknown name, replies with nil
      assert {:reply, nil, %Alfred.Names.State{known: %{}}} =
               Alfred.Names.Server.handle_call({:delete, "unknown"}, nil, new_state)
    end
  end

  describe "Alfred.Names.Server.handle_call({:lookup})" do
    @tag known_names_add: [], handle_add: :just_saw
    test "finds a known name", ctx do
      random_name = Enum.take_random(ctx.names, 1) |> List.first("unknown")

      assert {:reply, %Alfred.KnownName{name: ^random_name}, %Alfred.Names.State{known: known}} =
               Alfred.Names.Server.handle_call({:lookup, random_name}, nil, ctx.new_state)

      assert map_size(known) > 0
    end

    @tag known_names_add: [], handle_add: :just_saw
    test "returns unknown KnownName when name not found", ctx do
      # returns an invalid KnownName when name not found
      assert {:reply, %Alfred.KnownName{valid?: false}, %Alfred.Names.State{}} =
               Alfred.Names.Server.handle_call({:lookup, "foobar"}, nil, ctx.new_state)
    end
  end

  def handle_add(%{handle_add: :just_saw, state: state} = ctx) do
    {known_names, known_names_len} = known_names_from_ctx(ctx)

    assert {:reply, seen_names, %Alfred.Names.State{} = new_state} =
             Alfred.Names.Server.handle_call({:just_saw, known_names}, nil, state)

    # confirm all the seen names made it into state known
    assert [] = Enum.map(known_names, fn %{name: name} = _kn -> name end) -- seen_names
    assert length(seen_names) == known_names_len

    %{new_state: new_state, handle_result: seen_names}
  end

  def handle_add(_), do: :ok

  # KnownName missing?, mutable? default to false; ttl_ms to 30_000
  @kn_defs [callback: {:module, __MODULE__}]
  def known_name_add(%{known_name_add: opts}) do
    [name: Alfred.NamesAid.unique("server"), seen_at: DateTime.utc_now()]
    |> then(fn runtime_opts -> Keyword.merge(@kn_defs, runtime_opts ++ opts) end)
    |> Alfred.KnownName.new()
    |> then(fn kn -> %{known_name: kn, name: kn.name} end)
  end

  def known_name_add(_), do: :ok

  def known_names_add(%{known_names_add: opts}) do
    count = opts[:count] || 10

    for _ <- 1..count do
      [name: Alfred.NamesAid.unique("server"), seen_at: DateTime.utc_now()]
      |> then(fn runtime_opts -> [runtime_opts | @kn_defs] |> List.flatten() end)
      |> then(fn def_opts -> Keyword.merge(def_opts, opts) end)
      |> Alfred.KnownName.new()
    end
    |> then(fn known_names -> %{known_names: known_names, names: names(known_names)} end)
  end

  def known_names_add(_), do: :ok

  defp known_names_from_ctx(ctx) do
    case ctx do
      %{known_name: x} -> [x]
      %{known_names: x} -> x
    end
    |> then(fn known_names -> {known_names, length(known_names)} end)
  end

  # defp make_seen_at(seen_at) do
  #   case seen_at do
  #     x when is_integer(x) -> DateTime.utc_now() |> DateTime.add(x, :second)
  #     %DateTime{} = x -> x
  #     _ -> DateTime.utc_now()
  #   end
  # end

  defp names([%Alfred.KnownName{} | _] = known_names), do: for(kn <- known_names, do: kn.name)
end
