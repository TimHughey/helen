defmodule Alfred.NamesServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names_server: true

  alias Alfred.KnownName
  alias Alfred.Names.{Server, State}
  alias Alfred.NamesAid

  setup_all do
    res = start_supervised({Alfred.Names.Server, [names_server: __MODULE__]})

    pid = Should.Be.Ok.tuple_with_pid(res)
    call_opts = [names_server: __MODULE__]

    %{pid: pid, server_name: __MODULE__, call_opts: call_opts, state: %State{}}
  end

  setup [:known_name_add, :known_names_add, :handle_add]

  describe "Alfred.Names.Server starts" do
    test "via applicaton" do
      GenServer.whereis(Alfred.Names.Server) |> Should.Be.pid()
    end

    test "with specified name", %{server_name: server_name} do
      GenServer.whereis(server_name) |> Should.Be.pid()
    end
  end

  describe "Alfred.Names.Server.call" do
    test "handles when a server is not available" do
      Server.call({:foo}, names_server: Foo.Bar)
      |> Should.Be.Tuple.rc_and_val(:no_server, Foo.Bar)
    end

    test "handles when the server is available", ctx do
      Server.call(:known, ctx.call_opts)
      |> Should.Be.list()
    end
  end

  describe "Alfred.Names.Server.handle_call({:just_saw})" do
    @tag known_name_add: []
    test "processes an empty list", ctx do
      Server.handle_call({:just_saw, []}, nil, ctx.state)
      |> Should.Be.Reply.with_state()
      |> then(fn {res, _new_state} -> Should.Be.List.empty(res) end)
    end

    @tag known_names_add: [], handle_add: :just_saw
    test "processes a KnownName list", ctx do
      ctx.handle_result |> Should.Be.list()
    end
  end

  describe "Alfred.Names.Server.handle_call({:delete})" do
    @tag known_name_add: [], handle_add: :just_saw
    test "deletes a name", ctx do
      Server.handle_call({:delete, ctx.known_name.name}, nil, ctx.new_state)
      |> Should.Be.Reply.with_state()
      |> tap(fn {_res, new_state} -> Should.Be.Map.empty(new_state.known) end)
      |> tap(fn {res, _} -> Should.Be.equal(res, ctx.known_name.name) end)
    end

    @tag known_name_add: [], handle_add: :just_saw
    test "handles when a name does not exist", ctx do
      # attempt to delete an unknown name
      Server.handle_call({:delete, "unknown"}, nil, ctx.new_state)
      |> Should.Be.Reply.with_state()
      |> tap(fn {res, _} -> assert is_nil(res), Should.msg(res, "should be nil") end)
    end
  end

  describe "Alfred.Names.Server.handle_call({:lookup})" do
    @tag known_names_add: [], handle_add: :just_saw
    test "finds a known name", ctx do
      random_name = Enum.take_random(ctx.names, 1) |> List.first("unknown")

      {:lookup, random_name}
      |> Server.handle_call(nil, ctx.new_state)
      |> Should.Be.Reply.with_state()
      |> then(fn {res, _} -> Should.Be.Struct.with_key(res, KnownName, :name) end)
      |> then(fn name -> Should.Be.equal(name, random_name) end)
    end

    @tag known_names_add: [], handle_add: :just_saw
    test "returns unknown KnownName when name not found", ctx do
      {:lookup, "foobar"}
      |> Server.handle_call(nil, ctx.new_state)
      |> Should.Be.Reply.with_state()
      |> then(fn {res, _} -> Should.Be.Struct.with_key(res, KnownName, :valid?) end)
      |> then(fn valid? -> Should.Be.equal(valid?, false) end)
    end
  end

  def handle_add(%{handle_add: :just_saw, state: state} = ctx) do
    {known_names, known_names_len} = known_names_from_ctx(ctx)

    reply = Server.handle_call({:just_saw, known_names}, nil, state)
    {seen_names, new_state} = Should.Be.Reply.with_state(reply)

    # NOTE: Should.Be.List.with_length/2 returns the first element when
    # the iist length is one (1)
    Should.Be.List.with_length(seen_names, known_names_len)
    Should.Be.Map.with_keys(new_state.known, seen_names)

    %{new_state: new_state, handle_result: seen_names}
  end

  def handle_add(_), do: :ok

  # KnownName missing?, mutable? default to false; ttl_ms to 30_000
  @kn_defs [callback: {:module, __MODULE__}]
  def known_name_add(%{known_name_add: opts}) do
    [name: NamesAid.unique("server"), seen_at: DateTime.utc_now()]
    |> then(fn runtime_opts -> [runtime_opts | @kn_defs] |> List.flatten() end)
    |> then(fn def_opts -> Keyword.merge(def_opts, opts) end)
    |> KnownName.new()
    |> then(fn kn -> %{known_name: kn, name: kn.name} end)
  end

  def known_name_add(_), do: :ok

  def known_names_add(%{known_names_add: opts}) do
    count = opts[:count] || 10

    for _ <- 1..count do
      [name: NamesAid.unique("server"), seen_at: DateTime.utc_now()]
      |> then(fn runtime_opts -> [runtime_opts | @kn_defs] |> List.flatten() end)
      |> then(fn def_opts -> Keyword.merge(def_opts, opts) end)
      |> KnownName.new()
    end
    |> then(fn known_names -> %{known_names: known_names, names: names(known_names)} end)
  end

  def known_names_add(_), do: :ok

  # def make_known_name(%{make_known_name: opts}) do
  #   name = NamesAid.unique("server")
  #   cb = opts[:callback] || {:module, __MODULE__}
  #   at = opts[:seen_at] |> make_seen_at()
  #   mut? = if(is_nil(opts[:mutable]), do: false, else: opts[:mutable])
  #   ttl = opts[:ttl_ms] || 30_000
  #   miss? = if(is_nil(opts[:missing]), do: false, else: opts[:missing])
  #
  #   kn =
  #     %KnownName{name: name, callback: cb, mutable?: mut?, seen_at: at, ttl_ms: ttl, missing?: miss?}
  #     |> KnownName.validate()
  #
  #   %{known_name: kn}
  # end
  #
  # def make_known_name(_), do: :ok

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

  defp names([%KnownName{} | _] = known_names), do: for(kn <- known_names, do: kn.name)
end
