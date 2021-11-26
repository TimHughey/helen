defmodule Alfred.NamesStateTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names_state: true

  alias Alfred.KnownName
  alias Alfred.Names.State
  alias Alfred.NamesAid

  defmacro should_be_state_with_name(state, name) do
    quote location: :keep, bind_quoted: [state: state, name: name] do
      should_be_struct(state, State)

      found_kn = State.lookup(name, state)
      should_be_struct(found_kn, KnownName)
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

      should_be_state_with_name(res, kn.name)
    end

    test "handles adding multiple KnownName", %{state: state} do
      make_opts = %{make_known_name: []}
      multiple = for _x <- 1..10, do: make_known_name(make_opts).known_name

      res = State.add_or_update_known(multiple, state)

      for %KnownName{name: name} <- multiple do
        should_be_state_with_name(res, name)
      end
    end

    @tag make_known_name: []
    test "handles invalid KnownName", %{state: state, known_name: kn} do
      kn = %KnownName{kn | valid?: false}

      new_state = State.add_or_update_known(kn, state)

      should_be_struct(new_state, State)
      should_be_empty_map(new_state.known)
    end
  end

  @tag make_known_name: []
  test "Alfred.Names.State.delete_known/2 removes a name", %{state: state, known_name: kn} do
    new_state = State.add_or_update_known(kn, state)
    should_be_state_with_name(new_state, kn.name)

    res = State.delete_known(kn.name, new_state)

    unknown = State.lookup(kn.name, res)

    should_be_struct(unknown, KnownName)
    should_be_equal(unknown.valid?, false)
  end

  def make_known_name(%{make_known_name: opts}) do
    name = NamesAid.unique("state")
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
