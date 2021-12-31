defmodule Alfred.NamesStateTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_names_state: true

  defmacro assert_state_includes_name(state, name) do
    quote location: :keep, bind_quoted: [state: state, name: name] do
      assert %Alfred.Names.State{} = state

      assert known_name = Alfred.Names.State.lookup(name, state)
      assert(%Alfred.KnownName{} = known_name) && known_name
    end
  end

  setup_all do
    {:ok, %{state: struct(Alfred.Names.State)}}
  end

  setup [:make_known_name]

  describe "Alfred.Names.State.add_or_update" do
    @tag make_known_name: []
    test "handles adding one KnownName", %{state: state, known_name: kn} do
      res = Alfred.Names.State.add_or_update_known(kn, state)

      assert_state_includes_name(res, kn.name)
    end

    test "handles adding multiple KnownName", %{state: state} do
      make_opts = %{make_known_name: []}
      multiple = for _x <- 1..10, do: make_known_name(make_opts).known_name

      new_state = Alfred.Names.State.add_or_update_known(multiple, state)

      assert %Alfred.Names.State{known: %{}} = new_state

      Enum.all?(multiple, fn %{name: name} = _kn -> assert_state_includes_name(new_state, name) end)
    end

    @tag make_known_name: []
    test "handles invalid KnownName", %{state: state, known_name: kn} do
      kn = %Alfred.KnownName{kn | valid?: false}

      assert %Alfred.Names.State{known: %{}} = Alfred.Names.State.add_or_update_known(kn, state)
    end
  end

  @tag make_known_name: []
  test "Alfred.Names.State.delete_known/2 removes a name", %{state: state, known_name: kn} do
    new_state = Alfred.Names.State.add_or_update_known(kn, state)
    assert_state_includes_name(new_state, kn.name)

    new_state = Alfred.Names.State.delete_known(kn.name, new_state)
    assert %Alfred.Names.State{known: %{}} = new_state

    assert %Alfred.KnownName{valid?: false} = Alfred.Names.State.lookup(kn.name, new_state)
  end

  def make_known_name(%{make_known_name: opts}) do
    name = Alfred.NamesAid.unique("state")
    cb = opts[:callback] || {:module, __MODULE__}
    at = opts[:seen_at] |> make_seen_at()
    mut? = if(is_nil(opts[:mutable]), do: false, else: opts[:mutable])
    ttl = opts[:ttl_ms] || 30_000
    miss? = if(is_nil(opts[:missing]), do: false, else: opts[:missing])

    %Alfred.KnownName{name: name, callback: cb, mutable?: mut?, seen_at: at, ttl_ms: ttl, missing?: miss?}
    |> Alfred.KnownName.validate()
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
