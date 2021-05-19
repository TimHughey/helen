defmodule BroomTestShould do
  defmacro __using__(_opts) do
    quote do
      import BroomTestPretty
      import BroomTestShould
    end
  end

  defmacro should_be_cmd_equal(res, what) do
    quote location: :keep, bind_quoted: [res: res, what: what] do
      should_contain_key(res, :cmd)
      fail = pretty("cmd should equal #{inspect(what)}", res)
      assert res[:cmd] == what, fail
    end
  end

  defmacro should_be_non_empty_list(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("should be non-empty list", res)
      assert is_list(res), fail
      refute [] == res
    end
  end

  defmacro should_be_non_empty_list(ctx, what) when is_atom(what) do
    quote location: :keep, bind_quoted: [ctx: ctx, what: what] do
      fail = pretty(inspect(what, pretty: true), "should be non-empty list", ctx)
      list = get_in(ctx, [what])

      assert is_list(list), fail
      refute [] == list
    end
  end

  defmacro should_be_non_empty_list(msg, res) when is_binary(msg) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty(msg, "should be non-empty list", res)
      assert is_list(res), fail
      refute [] == res
    end
  end

  defmacro should_be_non_empty_map(msg, res) when is_binary(msg) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty(msg, "should be non-empty map", res)
      assert is_map(res), fail
      assert map_size(res) > 0, fail
    end
  end

  defmacro should_be_non_empty_map(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("should be non-empty map", res)
      assert is_map(res), fail
      assert map_size(res) > 0, fail
    end
  end

  defmacro should_be_ok_tuple(res) do
    quote location: :keep, bind_quoted: [res: res] do
      should_be_tuple(res)

      fail = pretty("rc should be :ok", res)
      {rc, _} = res
      assert :ok == rc, fail
    end
  end

  defmacro should_be_ok_tuple_with_val(res, val) do
    quote location: :keep, bind_quoted: [res: res, val: val] do
      should_be_ok_tuple(res)

      fail = pretty("val should be", val)
      {_, x} = res
      assert x == val, fail
    end
  end

  defmacro should_be_pid(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("should be a pid", res)
      assert is_pid(res), fail
    end
  end

  defmacro should_be_tuple(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("result should be a tuple", res)
      assert is_tuple(res), fail
    end
  end

  defmacro should_be_tuple_with_rc(res, rc) do
    quote location: :keep, bind_quoted: [res: res, rc: rc] do
      should_be_tuple(res)
      {res_rc, _} = res
      fail = pretty("rc should be #{inspect(rc)}", res)
      assert res_rc == rc
    end
  end

  defmacro should_be_status_map(x) do
    quote location: :keep, bind_quoted: [x: x] do
      should_be_non_empty_map(x)
      should_contain_key(x, :name)
      should_contain_key(x, :cmd)
      should_contain_key(x, :cmd_last)
      should_contain_key(x, :cmd_reported)
    end
  end

  defmacro should_be_struct(res, struct) do
    quote location: :keep, bind_quoted: [res: res, struct: struct] do
      fail = pretty("should be #{inspect(struct, pretty: true)}", res)
      assert is_struct(res), fail
      assert %struct{} = res, fail
    end
  end

  defmacro should_contain(res, [{key, val}]) do
    quote location: :keep, bind_quoted: [res: res, key: key, val: val] do
      fail = pretty("should contain key #{inspect(key)} val #{inspect(val)}", res)
      assert Enum.find(res, false, fn {k, v} -> k == key and v == val end), fail
    end
  end

  defmacro should_contain_key(res, what) do
    quote location: :keep, bind_quoted: [res: res, what: what] do
      fail = pretty("should contain key #{inspect(what)}", res)
      assert Enum.find(res, false, fn {k, _v} -> k == what end), fail
    end
  end

  defmacro should_contain_value(res, what) do
    quote location: :keep, bind_quoted: [res: res, what: what] do
      fail = pretty("should contain value #{inspect(what)}", res)

      assert Enum.find(res, false, fn
               {_k, v} -> v == what
               v -> v == what
             end),
             fail
    end
  end

  defmacro should_be_pending(x) do
    quote location: :keep, bind_quoted: [x: x] do
      should_be_status_map(x)
      fail = pretty("should be pending", x)
      assert is_map_key(x, :pending), fail
    end
  end

  defmacro should_not_be_pending(x) do
    quote location: :keep, bind_quoted: [x: x] do
      should_be_status_map(x)
      fail = pretty("should not be pending", x)
      refute is_map_key(x, :pending), fail
    end
  end

  defmacro should_not_be_ttl_expired(x) do
    quote location: :keep, bind_quoted: [x: x] do
      should_be_status_map(x)
      fail = pretty("should not be ttl expired", x)
      refute is_map_key(x, :ttl_expired), fail
    end
  end
end
