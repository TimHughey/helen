defmodule Alfred.KnownNameTest do
  use ExUnit.Case, async: true
  use Should
  use Alfred.NamesAid

  @moduletag alfred: true, alfred_known_name: true

  alias Alfred.KnownName

  defmacro should_be_missing(res, bool) do
    quote location: :keep, bind_quoted: [res: res, bool: bool] do
      should_be_struct(res, KnownName)
      fail = "valid? should be true"
      assert res.valid? == true, fail
      fail = "missing? should be #{inspect(bool)}"
      assert res.missing? == bool, fail
    end
  end

  setup [:make_known_name]

  describe "Alfred.KnownName.validate/1" do
    test "verifies a default KnownName is invalid" do
      res = %KnownName{} |> KnownName.validate()
      should_be_struct(res, KnownName)
      should_be_equal(res.valid?, false)
    end

    test "detects valid callbacks" do
      func = fn x, _y -> x end

      callbacks = [{:server, __MODULE__.Server}, {:module, __MODULE__}, func]

      for cb <- callbacks do
        res = %KnownName{callback: cb} |> KnownName.validate()
        should_be_struct(res, KnownName)
        should_be_equal(res.valid?, true)
      end
    end

    test "detects invalid seen_at" do
      kn = %KnownName{callback: {:module, __MODULE__}, seen_at: {:error, :datetime}}
      res = KnownName.validate(kn)
      should_be_struct(res, KnownName)
      should_be_equal(res.valid?, false)
    end

    test "detects invalid ttl_ms" do
      kn = %KnownName{callback: {:module, __MODULE__}, ttl_ms: 0}
      res = KnownName.validate(kn)
      should_be_struct(res, KnownName)
      should_be_equal(res.valid?, false)
    end
  end

  describe "Alfred.KnownName.detect_missing/2" do
    @tag make_known_name: [seen_at: -1, ttl_ms: 1]
    test "handles unspecified utc now", %{known_name: kn} do
      res = KnownName.detect_missing(kn)
      should_be_missing(res, true)
    end

    @tag make_known_name: [seen_at: -1, ttl_ms: 1]
    test "handle specified utc now", %{known_name: kn} do
      utc_now = DateTime.utc_now()
      res = KnownName.detect_missing(kn, utc_now)
      should_be_missing(res, true)
    end
  end

  describe "Alfred.KnownName.unknown/1" do
    test "creates an invalid KnownName" do
      name = NamesAid.unique("knownname")
      res = KnownName.unknown(name)

      should_be_struct(res, KnownName)
      should_be_equal(res.name, name)
      should_be_equal(res.valid?, false)
      should_be_equal(res.missing?, true)
    end
  end

  def make_known_name(%{make_known_name: opts}) do
    name = NamesAid.unique("knownname")
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
