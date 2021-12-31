defmodule Alfred.SeenNameTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_seen_name: true

  setup_all do
    {:ok, %{name_add: [type: :imm]}}
  end

  setup [:name_add, :seen_name_add]

  defmacro assert_seen_name(x, want_kv) do
    quote bind_quoted: [x: x, want_kv: want_kv] do
      assert %Alfred.SeenName{} = x

      # override fields with want kv
      want_seen_name = struct(x, want_kv)
      assert ^want_seen_name = x
    end
  end

  defmacro assert_seen_names(x, want_kv) do
    quote bind_quoted: [x: x, want_kv: want_kv] do
      Enum.all?(x, fn sn -> assert_seen_name(sn, want_kv) end)
    end
  end

  describe "Alfred.SeenName.validate/1" do
    @tag seen_name_add: []
    test "verifies a default SeenName is invalid", ctx do
      assert_seen_name(ctx.seen_name, valid?: false)
    end

    @tag seen_name_add: [seen_at: {:error, :datetime}]
    test "detects invalid seen_at", ctx do
      assert_seen_name(ctx.seen_name, valid?: false)
    end

    # NOTE: seen_at is calculated at compile time which is OK in this case
    @tag seen_name_add: [seen_at: DateTime.utc_now(), ttl_ms: 0]
    test "detects invalid ttl_ms", ctx do
      assert_seen_name(ctx.seen_name, valid?: false)
    end

    @tag seen_name_add: [seen_at: :now, ttl_ms: 1000]
    test "verifies a well formed SeenName", ctx do
      assert_seen_name(ctx.seen_name, valid?: true)
    end

    @tag seen_name_add: [count: 100]
    test "create list of SeenNames and confirm validate excludes invalid SeenName", ctx do
      # NOTE: manually add an invalid SeenName then validate again

      seen_names = [%Alfred.SeenName{} | ctx.seen_names] |> Alfred.SeenName.validate()

      assert_seen_names(seen_names, valid?: true)
      assert length(seen_names) == 100
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp name_add(ctx), do: Alfred.NamesAid.name_add(ctx)

  defp seen_name_add(%{seen_name_add: []}) do
    %{seen_name: %Alfred.SeenName{} |> Alfred.SeenName.validate()}
  end

  defp seen_name_add(%{seen_name_add: [{:count, count}]}) do
    auto_fields = [ttl_ms: 1000, seen_at: DateTime.utc_now()]
    # create the requested count of valid seen names
    auto_seen_names =
      Enum.map(1..count, fn _x ->
        struct(Alfred.SeenName, auto_fields ++ [name: Alfred.NamesAid.unique("autoseenname")])
      end)

    %{seen_names: Alfred.SeenName.validate(auto_seen_names)}
  end

  defp seen_name_add(%{name: name, seen_name_add: fields}) do
    {at_opt, fields_rest} = Keyword.pop(fields, :seen_at, :now)

    seen_at = if(at_opt == :now, do: DateTime.utc_now(), else: at_opt)

    struct(Alfred.SeenName, fields_rest ++ [name: name, seen_at: seen_at])
    |> Alfred.SeenName.validate()
    |> then(fn seen_name -> %{seen_name: seen_name} end)
  end

  defp seen_name_add(_), do: :ok
end
