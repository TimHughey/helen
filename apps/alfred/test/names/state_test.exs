defmodule Alfred.NamesStateTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names_state: true

  alias Alfred.KnownName
  alias Alfred.Names.State
  alias Alfred.NamesAid

  defmacro assert_state_includes_name(state, name) do
    quote location: :keep, bind_quoted: [state: state, name: name] do
      Should.Be.State.with_key(state, :known)
      |> then(fn {state, _} -> State.lookup(name, state) end)
      |> Should.Be.struct(KnownName)

      # returns known name
    end
  end

  setup_all do
    {:ok, %{state: struct(State)}}
  end

  setup [:make_known_name]

  describe "Alfred.Names.State.add_or_update" do
    @tag make_known_name: []
    test "handles adding one KnownName", %{state: state, known_name: kn} do
      res = State.add_or_update_known(kn, state)

      assert_state_includes_name(res, kn.name)
    end

    test "handles adding multiple KnownName", %{state: state} do
      make_opts = %{make_known_name: []}
      multiple = for _x <- 1..10, do: make_known_name(make_opts).known_name

      res = State.add_or_update_known(multiple, state)

      for %KnownName{name: name} <- multiple do
        assert_state_includes_name(res, name)
      end
    end

    @tag make_known_name: []
    test "handles invalid KnownName", %{state: state, known_name: kn} do
      kn = %KnownName{kn | valid?: false}

      State.add_or_update_known(kn, state)
      |> Should.Be.State.with_key(:known)
      # NOTE: Should.Be.StatE.WITH_key/2 returns tuple of {state, key_value}
      |> then(fn {_state, known} -> Should.Be.map(known) end)
    end
  end

  @tag make_known_name: []
  test "Alfred.Names.State.delete_known/2 removes a name", %{state: state, known_name: kn} do
    new_state = State.add_or_update_known(kn, state)
    assert_state_includes_name(new_state, kn.name)

    State.delete_known(kn.name, new_state)
    |> Should.Be.State.with_key(:known)
    |> then(fn {state, _} -> State.lookup(kn.name, state) end)
    |> Should.Be.Struct.with_all_key_value(KnownName, valid?: false)
  end

  def make_known_name(%{make_known_name: opts}) do
    name = NamesAid.unique("state")
    cb = opts[:callback] || {:module, __MODULE__}
    at = opts[:seen_at] |> make_seen_at()
    mut? = if(is_nil(opts[:mutable]), do: false, else: opts[:mutable])
    ttl = opts[:ttl_ms] || 30_000
    miss? = if(is_nil(opts[:missing]), do: false, else: opts[:missing])

    %KnownName{name: name, callback: cb, mutable?: mut?, seen_at: at, ttl_ms: ttl, missing?: miss?}
    |> KnownName.validate()
    |> then(fn kn -> %{known_name: kn} end)
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
