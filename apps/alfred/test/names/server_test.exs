defmodule Alfred.NamesServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names_server: true

  alias Alfred.KnownName
  alias Alfred.Names.{Server, State}
  alias Alfred.NamesAid

  setup_all do
    res = start_supervised({Alfred.Names.Server, [names_server: __MODULE__]})

    pid = should_be_ok_tuple_with_pid(res)
    call_opts = [names_server: __MODULE__]

    %{pid: pid, server_name: __MODULE__, call_opts: call_opts, state: %State{}}
  end

  setup [:make_known_name]

  describe "Alfred.Names.Server starts" do
    test "via applicaton" do
      res = GenServer.whereis(Alfred.Names.Server)

      should_be_pid(res)
    end

    test "with specified name", %{server_name: server_name} do
      res = GenServer.whereis(server_name)

      should_be_pid(res)
    end
  end

  describe "Alfred.Names.Server.call" do
    test "handles when a server is not available" do
      res = Server.call({:foo}, names_server: Foo.Bar)

      should_be_match(res, {:no_server, Foo.Bar})
    end

    test "handles when the server is available", ctx do
      res = Server.call(:known, ctx.call_opts)

      should_be_list(res)
    end
  end

  describe "Alfred.Names.Server.handle_call({:just_saw})" do
    @tag make_known_name: []
    test "processes an empty list", %{state: state} do
      res = Server.handle_call({:just_saw, []}, nil, state)

      {results, _new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_empty_list(results)
    end

    test "processes a KnownName list", %{state: state} do
      opts = %{make_known_name: []}
      list = for _x <- 1..10, do: make_known_name(opts).known_name

      res = Server.handle_call({:just_saw, list}, nil, state)

      {results, new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_non_empty_list_with_length(results, length(list))

      names = for %KnownName{} = kn <- list, do: kn.name

      should_be_map_with_keys(new_state.known, names)
    end
  end

  describe "Alfred.Names.Server.handle_call({:delete})" do
    @tag make_known_name: []
    test "deletes a name", %{known_name: kn, state: state} do
      res = Server.handle_call({:just_saw, [kn]}, nil, state)
      {results, new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_non_empty_list_with_length(results, 1)
      should_be_equal(hd(results), kn.name)
      should_be_map_with_keys(new_state.known, [kn.name])

      res = Server.handle_call({:delete, kn.name}, nil, new_state)
      {result, new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_empty_map(new_state.known)
      should_be_equal(result, kn.name)
    end

    @tag make_known_name: []
    test "handles when a name does not exist", %{known_name: kn, state: state} do
      res = Server.handle_call({:just_saw, [kn]}, nil, state)
      {results, new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_non_empty_list_with_length(results, 1)
      should_be_equal(hd(results), kn.name)
      should_be_map_with_keys(new_state.known, [kn.name])

      res = Server.handle_call({:delete, "unknown"}, nil, new_state)
      {result, new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_non_empty_map(new_state.known)
      should_be_equal(result, nil)
    end
  end

  describe "Alfred.Names.Server.handle_call({:lookup})" do
    test "finds a known name", %{state: state} do
      opts = %{make_known_name: []}
      list = for _x <- 1..10, do: make_known_name(opts).known_name

      res = Server.handle_call({:just_saw, list}, nil, state)

      {results, new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_non_empty_list_with_length(results, length(list))

      names = for %KnownName{} = kn <- list, do: kn.name

      random_name = Enum.take_random(names, 1) |> hd()

      res = Server.handle_call({:lookup, random_name}, nil, new_state)
      {results, _new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_struct(results, KnownName)
      should_be_equal(results.name, random_name)
    end

    test "returns unknown KnownName when name not found", %{state: state} do
      res = Server.handle_call({:lookup, "foobar"}, nil, state)
      {results, _new_state} = should_be_reply_tuple_with_state(res, State)

      should_be_struct(results, KnownName)
      should_be_equal(results.valid?, false)
    end
  end

  def make_known_name(%{make_known_name: opts}) do
    name = NamesAid.unique("server")
    cb = opts[:callback] || {:module, __MODULE__}
    at = opts[:seen_at] |> make_seen_at()
    mut? = if(is_nil(opts[:mutable]), do: false, else: opts[:mutable])
    ttl = opts[:ttl_ms] || 30_000
    miss? = if(is_nil(opts[:missing]), do: false, else: opts[:missing])

    kn =
      %KnownName{name: name, callback: cb, mutable?: mut?, seen_at: at, ttl_ms: ttl, missing?: miss?}
      |> KnownName.validate()

    %{known_name: kn}
  end

  def make_known_name(ctx), do: ctx

  defp make_seen_at(seen_at) do
    case seen_at do
      x when is_integer(x) -> DateTime.utc_now() |> DateTime.add(x, :second)
      %DateTime{} = x -> x
      _ -> DateTime.utc_now()
    end
  end
end
