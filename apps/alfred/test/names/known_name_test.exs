defmodule Alfred.KnownNameTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_known_name: true

  defmacro assert_known_name(x, check) do
    quote bind_quoted: [x: x, check: check] do
      cond do
        is_atom(check) ->
          valid? = check == :valid
          %Alfred.KnownName{valid?: ^valid?} = x

        is_list(check) ->
          # confirm x is a known name
          assert %Alfred.KnownName{} = x

          # override fields with check fields
          want_kn = struct(x, check)
          assert ^want_kn = x
      end
    end
  end

  defmacro assert_known_name_list(x, check) do
    quote bind_quoted: [x: x, check: check] do
      Enum.all?(x, fn kn -> assert_known_name(kn, check) end)
    end
  end

  defmacro assert_missing(x, bool) do
    quote bind_quoted: [x: x, bool: bool] do
      assert_known_name(x, valid?: true, missing?: bool)
    end
  end

  setup [:known_name_add]

  describe "Alfred.KnownName.validate/1" do
    @tag known_name_add: []
    test "verifies a default KnownName is invalid", ctx do
      assert_known_name(ctx.known_name, :not_valid)
    end

    test "detects valid callbacks" do
      func = fn x, _y -> x end

      callbacks = [{:server, __MODULE__.Server}, {:module, __MODULE__}, func]

      kn_list =
        Enum.map(callbacks, fn x -> struct(Alfred.KnownName, callback: x) |> Alfred.KnownName.validate() end)

      assert_known_name_list(kn_list, valid: true)
    end

    @tag known_name_add: [seen_at: {:error, :datetime}]
    test "detects invalid seen_at", ctx do
      assert_known_name(ctx.known_name, :not_valid)
    end

    @tag known_name_add: [ttl_ms: 0]
    test "detects invalid ttl_ms", ctx do
      assert_known_name(ctx.known_name, :not_valid)
    end
  end

  describe "Alfred.KnownName.detect_missing/2" do
    @tag known_name_add: [seen_at: -1, ttl_ms: 1]
    test "handles unspecified utc now", %{known_name: kn} do
      Alfred.KnownName.detect_missing(kn)
      |> assert_missing(true)
    end

    @tag known_name_add: [seen_at: -1, ttl_ms: 1]
    test "handle specified utc now", %{known_name: kn} do
      utc_now = DateTime.utc_now()

      Alfred.KnownName.detect_missing(kn, utc_now)
      |> assert_missing(true)
    end
  end

  describe "Alfred.KnownName.unknown/1" do
    test "creates an invalid KnownName" do
      name = Alfred.NamesAid.unique("knownname")

      Alfred.KnownName.unknown(name)
      |> assert_known_name(name: name, valid?: false, missing?: true)
    end
  end

  def known_name_add(%{known_name_add: []}) do
    %{known_name: %Alfred.KnownName{} |> Alfred.KnownName.validate()}
  end

  def known_name_add(%{known_name_add: opts}) do
    name = Alfred.NamesAid.unique("knownname")
    cb = opts[:callback] || {:module, __MODULE__}
    at = opts[:seen_at] |> make_seen_at()
    mut? = if(is_nil(opts[:mutable]), do: false, else: opts[:mutable])
    ttl = opts[:ttl_ms] || 30_000
    miss? = if(is_nil(opts[:missing]), do: false, else: opts[:missing])

    [name: name, callback: cb, seen_at: at, mutable?: mut?, ttl_ms: ttl, missing?: miss?]
    |> then(fn fields -> struct(Alfred.KnownName, fields) end)
    |> Alfred.KnownName.validate()
    |> then(fn kn -> %{known_name: kn} end)
  end

  def known_name_add(ctx), do: ctx

  defp make_seen_at(seen_at) do
    case seen_at do
      x when is_integer(x) -> DateTime.utc_now() |> DateTime.add(x, :second)
      %DateTime{} = x -> x
      x when is_tuple(x) -> x
      _ -> DateTime.utc_now()
    end
  end
end
