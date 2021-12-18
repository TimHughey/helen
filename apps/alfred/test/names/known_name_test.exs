defmodule Alfred.KnownNameTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_known_name: true

  alias Alfred.KnownName
  alias Alfred.NamesAid

  defmacro assert_known_name(x, check) do
    quote location: :keep, bind_quoted: [x: x, check: check] do
      cond do
        is_atom(check) ->
          Should.Be.Struct.with_all_key_value(x, KnownName, valid?: check == :valid)

        is_list(check) ->
          Should.Be.Struct.with_all_key_value(x, KnownName, check)
      end
    end
  end

  defmacro assert_missing(x, bool) do
    quote location: :keep, bind_quoted: [x: x, bool: bool] do
      want_kv = [valid?: true, missing?: bool]
      Should.Be.Struct.with_all_key_value(x, KnownName, want_kv)
    end
  end

  setup [:make_known_name]

  describe "Alfred.KnownName.validate/1" do
    test "verifies a default KnownName is invalid" do
      %KnownName{}
      |> KnownName.validate()
      |> assert_known_name(:not_valid)
    end

    test "detects valid callbacks" do
      func = fn x, _y -> x end

      callbacks = [{:server, __MODULE__.Server}, {:module, __MODULE__}, func]

      for cb <- callbacks do
        %KnownName{callback: cb}
        |> KnownName.validate()
        |> assert_known_name(:valid)
      end
    end

    test "detects invalid seen_at" do
      %KnownName{callback: {:module, __MODULE__}, seen_at: {:error, :datetime}}
      |> KnownName.validate()
      |> assert_known_name(:not_valid)
    end

    test "detects invalid ttl_ms" do
      %KnownName{callback: {:module, __MODULE__}, ttl_ms: 0}
      |> KnownName.validate()
      |> assert_known_name(:not_valid)
    end
  end

  describe "Alfred.KnownName.detect_missing/2" do
    @tag make_known_name: [seen_at: -1, ttl_ms: 1]
    test "handles unspecified utc now", %{known_name: kn} do
      KnownName.detect_missing(kn)
      |> assert_missing(true)
    end

    @tag make_known_name: [seen_at: -1, ttl_ms: 1]
    test "handle specified utc now", %{known_name: kn} do
      utc_now = DateTime.utc_now()

      KnownName.detect_missing(kn, utc_now)
      |> assert_missing(true)
    end
  end

  describe "Alfred.KnownName.unknown/1" do
    test "creates an invalid KnownName" do
      name = NamesAid.unique("knownname")

      KnownName.unknown(name)
      |> assert_known_name(name: name, valid?: false, missing?: true)
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
