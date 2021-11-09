defmodule Should do
  defmacro __using__(_opts) do
    quote do
      import Should
    end
  end

  defmacro should_be_simple_ok(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = "#{res} should be :ok"
      assert res == :ok, fail
    end
  end

  defmacro should_be_cmd_equal(res, what) do
    quote location: :keep, bind_quoted: [res: res, what: what] do
      should_contain_key(res, :cmd)
      fail = pretty("cmd should equal #{inspect(what)}", res)
      assert res[:cmd] == what, fail
    end
  end

  defmacro should_be_datetime(res) do
    quote location: :keep, bind_quoted: [res: res] do
      should_be_struct(res, DateTime)
    end
  end

  defmacro should_be_empty_list(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("should be empty list", res)
      assert is_list(res), fail
      assert [] == res, fail
    end
  end

  defmacro should_be_datetime_greater_than(res, dt) do
    quote location: :keep, bind_quoted: [res: res, dt: dt] do
      fail = "#{inspect(res)} should be greater than #{inspect(dt)}"
      assert DateTime.compare(dt, res) == :gt, fail
    end
  end

  defmacro should_be_equal(res, expected) do
    quote location: :keep, bind_quoted: [res: res, expected: expected] do
      fail = "#{inspect(res)} should be equal to #{inspect(expected)}"
      assert res == expected
    end
  end

  defmacro should_be_map_with_keys(map, keys) do
    quote location: :keep, bind_quoted: [map: map, keys: keys] do
      should_be_non_empty_map(map)

      for key <- keys do
        fail = pretty("should contain key #{inspect(key)}", map)
        assert is_map_key(map, key), fail
      end
    end
  end

  defmacro should_be_match(res, to_match) do
    quote location: :keep, bind_quoted: [res: res, to_match: to_match] do
      res_binary = inspect(res, pretty: true)
      to_match_binary = inspect(res, pretty: true)
      fail = "#{res_binary} should match #{to_match_binary}"
      assert to_match = res, fail
    end
  end

  defmacro should_be_non_empty_list(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("should be non-empty list", res)
      assert is_list(res), fail
      refute [] == res, fail
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

  defmacro should_be_error_tuple(res) do
    quote location: :keep, bind_quoted: [res: res] do
      should_be_tuple_with_size(res, 2)

      fail = pretty("rc should be :error", res)
      {rc, res_binary} = res
      assert :error == rc, fail
    end
  end

  defmacro should_be_error_tuple_with_binary(res, binary) do
    quote location: :keep, bind_quoted: [res: res, binary: binary] do
      should_be_tuple_with_size(res, 2)

      fail = pretty("rc should be :error", res)
      {rc, res_binary} = res
      assert :error == rc, fail

      fail = pretty("tuple element 1 should be binary", res_binary)
      assert is_binary(res_binary), fail

      fail = pretty("#{res_binary} should contain", binary)
      assert String.contains?(res_binary, binary), fail
    end
  end

  defmacro should_be_error_tuple_with_ecto_changeset(res) do
    quote location: :keep, bind_quoted: [res: res] do
      should_be_tuple_with_size(res, 2)

      fail = pretty("rc should be :error", res)
      {rc, changeset} = res
      assert :error == rc, fail

      should_be_struct(changeset, Ecto.Changeset)
    end
  end

  defmacro should_be_error_tuple_with_struct(res, struct) do
    quote location: :keep, bind_quoted: [res: res, struct: struct] do
      should_be_tuple_with_size(res, 2)
      {rc, res_struct} = res

      should_be_equal(rc, :error)
      should_be_struct(res_struct, struct)
    end
  end

  defmacro should_be_failed_tuple_with_struct(res, struct) do
    quote location: :keep, bind_quoted: [res: res, struct: struct] do
      should_be_tuple_with_size(res, 2)
      {rc, res_struct} = res

      should_be_equal(rc, :failed)
      should_be_struct(res_struct, struct)
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

  defmacro should_be_ok_tuple_with_size(res, size) do
    quote location: :keep, bind_quoted: [res: res, size: size] do
      should_be_tuple_with_size(res, size)

      fail = pretty("rc should be :ok", res)
      rc = elem(res, 0)
      assert :ok == rc, fail
    end
  end

  defmacro should_be_ok_tuple_with_struct(res, struct) do
    quote location: :keep, bind_quoted: [res: res, struct: struct] do
      should_be_tuple_with_size(res, 2)

      fail = pretty("rc should be :ok", res)
      {rc, res_struct} = res
      assert :ok == rc, fail

      fail = pretty("should be #{inspect(struct, pretty: true)}", res_struct)
      assert is_struct(res_struct), fail
      assert res_struct.__struct__ == struct, fail
    end
  end

  defmacro should_be_ok_tuple_with_schema(res, schema) do
    quote location: :keep, bind_quoted: [res: res, schema: schema] do
      should_be_tuple(res)

      fail = pretty("rc should be :ok", res)
      assert :ok == elem(res, 0), fail

      should_be_schema(elem(res, 1), schema)
    end
  end

  defmacro should_be_ok_tuple_with_val(res, val) do
    quote location: :keep, bind_quoted: [res: res, val: val] do
      should_be_ok_tuple(res)

      fail = pretty("val should be ", val)
      {_, x} = res
      assert x == val, fail
    end
  end

  defmacro should_be_ok_tuple_with_pid(res) do
    quote location: :keep, bind_quoted: [res: res] do
      should_be_tuple_with_size(res, 2)

      {:ok, pid} = res
      fail = pretty("should be {:ok, pid}: ", res)
      assert is_pid(pid), fail

      pid
    end
  end

  defmacro should_be_not_found_tuple_with_binary(res, binary) do
    quote location: :keep, bind_quoted: [res: res, binary: binary] do
      should_be_tuple_with_size(res, 2)
      {rc, res_binary} = res

      fail = pretty("rc should be :not_found", res)
      assert :not_found == rc, fail

      fail = pretty("tuple element 1 should be binary", res_binary)
      assert is_binary(res_binary), fail

      fail = pretty("#{res_binary} should contain", binary)
      assert String.contains?(res_binary, binary), fail
    end
  end

  defmacro should_be_pid(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("should be a pid", res)
      assert is_pid(res), fail
    end
  end

  defmacro should_be_rc_tuple_with_struct(res, rc, struct) do
    quote location: :keep, bind_quoted: [res: res, rc: rc, struct: struct] do
      should_be_tuple_with_size(res, 2)

      {res_rc, res_struct} = res
      should_be_equal(res_rc, rc)
      should_be_struct(res_struct, struct)
    end
  end

  defmacro should_be_tuple(res) do
    quote location: :keep, bind_quoted: [res: res] do
      fail = pretty("result should be a tuple", res)
      assert is_tuple(res), fail
    end
  end

  defmacro should_be_tuple_with_size(res, size) do
    quote location: :keep, bind_quoted: [res: res, size: size] do
      fail = pretty("result should be a tuple", res)
      assert is_tuple(res), fail

      fail = pretty("tuple should be size #{size}", res)
      assert tuple_size(res) == size, fail
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

  def should_be_tuple_with_rc_and_val(res, rc, val) do
    quote location: :keep, bind_quoted: [res: res, rc: rc, val: val] do
      should_be_tuple_with_size(res, 2)
      {res_rc, res_val} = res

      should_be_equal(res_rc, rc)
      should_be_equal(res_val, val)
    end
  end

  def should_be_msg_tuple_with_mod_and_struct(res, mod, struct) do
    quote location: :keep, bind_quoted: [res: res, mod: mod, struct: struct] do
      should_be_tuple_with_size(res, 2)
      {res_mod, res_struct} = res

      should_be_equal(res_mod, mod)
      should_be_struct(res_struct, struct)
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
      assert res.__struct__ == struct, fail
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

  defmacro should_be_schema(res, schema) do
    quote location: :keep, bind_quoted: [res: res, schema: schema] do
      fail = pretty("should be #{inspect(schema)}", res)
      assert is_struct(res), fail
      assert res.__struct__ == schema, fail
      assert res.__meta__.schema == schema, fail
      assert res.id, fail
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

  defmacro should_be_noreply_tuple_with_state(res, struct) do
    quote location: :keep, bind_quoted: [res: res, struct: struct] do
      fail = pretty("result should be a noreply tuple with state", res)
      assert is_tuple(res), fail
      assert tuple_size(res) == 2, fail
      assert elem(res, 0) == :noreply, fail
      assert elem(res, 1) |> is_struct(), fail
      assert elem(res, 1).__struct__ == struct, fail
    end
  end

  def pretty(msg, x), do: [msg, "\n", inspect(x, pretty: true)] |> IO.iodata_to_binary()
end
