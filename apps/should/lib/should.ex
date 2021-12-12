defmodule Should do
  defmacro __using__(_opts) do
    quote do
      import Should
      require Should.Be
      require Should.Be.{DateTime, Integer, Invalid}
      require Should.Be.{List, Map, NonEmpty, NoReply}
      require Should.Be.{Ok, Reply}
      require Should.Be.{Schema, Server, State, Struct, Tuple}
      require Should.Contain
    end
  end

  @doc """
  Asserts true if `check` is greater than `dt`

  ```assert DateTime.compare(check, dt) == :gt, msg(check, "should be greater than", dt)```
  """
  defmacro should_be_datetime_greater_than(check, dt) do
    quote bind_quoted: [check: check, dt: dt] do
      assert DateTime.compare(check, dt) == :gt, msg(check, "should be greater than", dt)
    end
  end

  defmacro should_be_empty_list(check) do
    quote bind_quoted: [check: check] do
      assert is_list(check), msg(check, "should be empty list")
      assert [] == check, msg(check, "should be empty list")
    end
  end

  defmacro should_be_function_exported(mfa) do
    quote bind_quoted: [mfa: mfa] do
      {mod, func, arity} = should_be_tuple_with_size(mfa, 3)

      fail = msg(mfa, "should be exported")
      assert function_exported?(mod, func, arity)
    end
  end

  defmacro should_be_integer(check) do
    quote bind_quoted: [check: check] do
      assert is_integer(check), msg(check, "should be integer")
    end
  end

  defmacro should_be_reference(check) do
    quote bind_quoted: [check: check] do
      assert is_reference(check), msg(check, "should be reference")
    end
  end

  defmacro should_be_empty_map(check) do
    quote bind_quoted: [check: check] do
      assert is_map(check), msg(check, "should be empty map")
      assert map_size(check) == 0, msg(check, "should be empty map")
    end
  end

  defmacro should_be_equal(lhs, rhs) do
    quote bind_quoted: [lhs: lhs, rhs: rhs] do
      assert lhs == rhs, msg(lhs, "should be equal to", rhs)
    end
  end

  defmacro should_be_refuted(lhs, rhs) do
    quote bind_quoted: [lhs: lhs, rhs: rhs] do
      refute lhs == rhs, msg(lhs, "should be refuted with", rhs)
    end
  end

  defmacro should_be_map(map) do
    quote bind_quoted: [map: map] do
      assert is_map(map), msg(map, "should be a map")
    end
  end

  defmacro should_be_map_with_keys(map, keys) do
    quote bind_quoted: [map: map, keys: keys] do
      Should.Be.NonEmpty.map(map)

      for key <- keys do
        assert is_map_key(map, key), msg(map, "should contain key #{inspect(key)}")
      end
    end
  end

  defmacro should_be_map_with_size(map, size) do
    quote bind_quoted: [map: map, size: size] do
      Should.Be.NonEmpty.map(map)
      assert map_size(map) == size, msg(map, "should be size", size)
    end
  end

  defmacro should_be_match(rhs, lhs) do
    quote bind_quoted: [rhs: rhs, lhs: lhs] do
      assert match?(^rhs, lhs), msg(lhs, "should match", rhs)
    end
  end

  defmacro should_be_non_empty_list(lhs) do
    quote bind_quoted: [lhs: lhs] do
      assert is_list(lhs), msg(lhs, "should be empty list")
      refute [] == lhs, msg(lhs, "should be empty list")
    end
  end

  defmacro should_be_non_empty_list_with_length(check, len) do
    quote bind_quoted: [check: check, len: len] do
      fail = msg(check, "should be list with length", len)
      assert is_list(check), fail
      refute [] == check, fail
      assert length(check) == len, fail
    end
  end

  defmacro should_be_error_tuple(check) do
    quote bind_quoted: [check: check] do
      should_be_tuple_with_size(check, 2)

      {rc, checkult} = check
      assert :error == rc, msg(check, "should have rc == :error")

      checkult
    end
  end

  defmacro should_be_error_tuple_with_binary(check, binary) do
    quote bind_quoted: [check: check, binary: binary] do
      check_binary = should_be_error_tuple(check)

      assert is_binary(check_binary), msg(check, "tuple element 1 should be binary")
      assert String.contains?(check_binary, binary), msg(check, "tuple element 1 should contain", binary)
    end
  end

  defmacro should_be_error_tuple_with_ecto_changeset(check) do
    quote bind_quoted: [check: check] do
      checkult = should_be_error_tuple(check)
      should_be_struct(checkult, Ecto.Changeset)
    end
  end

  defmacro should_be_error_tuple_with_struct(check, struct) do
    quote bind_quoted: [check: check, struct: struct] do
      should_be_tuple_with_size(check, 2)
      {rc, check_struct} = check

      should_be_equal(rc, :error)
      should_be_struct(check_struct, struct)
    end
  end

  defmacro should_be_failed_tuple_with_struct(check, struct) do
    quote bind_quoted: [check: check, struct: struct] do
      should_be_tuple_with_size(check, 2)
      {rc, check_struct} = check

      should_be_equal(rc, :failed)
      should_be_struct(check_struct, struct)
    end
  end

  defmacro should_be_invalid_tuple(check) do
    quote bind_quoted: [check: check] do
      should_be_tuple_with_size(check, 2)
      {rc, invalid_reason} = check

      should_be_equal(rc, :invalid)
      invalid_reason
    end
  end

  defmacro should_be_ok_tuple(check) do
    quote bind_quoted: [check: check] do
      should_be_tuple_with_size(check, 2)

      {rc, returned} = check
      assert :ok == rc, msg(check, "should have rc == :ok")

      returned
    end
  end

  defmacro should_be_ok_tuple_with_size(check, size) do
    quote bind_quoted: [check: check, size: size] do
      should_be_tuple_with_size(check, size)

      rc = elem(check, 0)
      assert :ok == rc, msg(check, "should have rc == :ok")
    end
  end

  defmacro should_be_ok_tuple_with_struct(check, struct) do
    quote bind_quoted: [check: check, struct: struct] do
      check_struct = should_be_ok_tuple(check)

      fail = msg(check, "should have struct", check_struct)
      assert is_struct(check_struct), fail
      assert check_struct.__struct__ == struct, fail

      check_struct
    end
  end

  defmacro should_be_ok_tuple_with_schema(check, schema) do
    quote bind_quoted: [check: check, schema: schema] do
      checkult = should_be_ok_tuple(check)

      should_be_schema(checkult, schema)
    end
  end

  defmacro should_be_ok_tuple_with_val(check, val) do
    quote bind_quoted: [check: check, val: val] do
      checkult = should_be_ok_tuple(check)

      should_be_equal(checkult, val)
    end
  end

  defmacro should_be_ok_tuple_with_pid(check) do
    quote bind_quoted: [check: check] do
      pid = should_be_ok_tuple(check)
      assert is_pid(pid), msg(pid, "should be a pid")

      pid
    end
  end

  defmacro should_be_not_found_tuple_with_binary(check, binary) do
    quote bind_quoted: [check: check, binary: binary] do
      should_be_tuple_with_size(check, 2)
      {rc, check_binary} = check

      assert :not_found == rc, msg(check, "should have rc == #{inspect(rc)}")

      assert is_binary(check_binary), msg(check, "element 1 should be binary")

      assert String.contains?(check_binary, binary), msg(check, "should contain binary", binary)
    end
  end

  defmacro should_be_pid(check) do
    quote bind_quoted: [check: check] do
      assert is_pid(check), msg(check, "should be a pid")
    end
  end

  defmacro should_be_rc_tuple_with_struct(check, rc, struct) do
    quote bind_quoted: [check: check, rc: rc, struct: struct] do
      should_be_tuple_with_size(check, 2)

      {check_rc, check_struct} = check
      should_be_equal(check_rc, rc)
      should_be_struct(check_struct, struct)
    end
  end

  defmacro should_be_tuple(lhs) do
    quote bind_quoted: [lhs: lhs] do
      assert is_tuple(lhs), msg(lhs, "should be a tuple")

      lhs
    end
  end

  defmacro should_be_tuple_with_size(tuple, size) do
    quote bind_quoted: [tuple: tuple, size: size] do
      should_be_tuple(tuple)
      assert tuple_size(tuple) == size, msg(tuple, "should be size", size)

      tuple
    end
  end

  defmacro should_be_tuple_with_rc(check, rc) do
    quote bind_quoted: [check: check, rc: rc] do
      {tuple_rc, tuple_val} = should_be_tuple(check)
      assert tuple_rc == rc, msg(check, "should have rc", rc)

      tuple_val
    end
  end

  defmacro should_be_tuple_with_rc_and_val(check, rc, val) do
    quote bind_quoted: [check: check, rc: rc, val: val] do
      should_be_tuple_with_size(check, 2)
      {check_rc, check_val} = check

      should_be_equal(check_rc, rc)
      should_be_equal(check_val, val)
    end
  end

  defmacro should_be_msg_tuple_with_mod_and_struct(check, mod, struct) do
    quote bind_quoted: [check: check, mod: mod, struct: struct] do
      should_be_tuple_with_size(check, 2)
      {check_mod, check_struct} = check

      should_be_equal(check_mod, mod)
      should_be_struct(check_struct, struct)

      check_struct
    end
  end

  defmacro should_be_status_map(x) do
    quote bind_quoted: [x: x] do
      Should.Be.NonEmpty.map(x)
      should_contain_key(x, :name)
      should_contain_key(x, :cmd)
      should_contain_key(x, :cmd_last)
      should_contain_key(x, :cmd_reported)
    end
  end

  defmacro should_be_timer_with_remaining_ms(ref, ms) do
    quote bind_quoted: [ref: ref, ms: ms] do
      should_be_reference(ref)

      left_ms = Process.read_timer(ref)

      refute is_nil(left_ms), msg(ref, "does not reference a timer")
      assert_in_delta left_ms, ms, 100, msg(left_ms, "should be close to #{ms}")
    end
  end

  defmacro should_be_struct(check, struct) do
    quote bind_quoted: [check: check, struct: struct] do
      fail = msg(check, "should be struct", struct)
      assert is_struct(check), fail
      assert check.__struct__ == struct, fail
    end
  end

  defmacro should_contain(check, [{key, val}] = rhs) do
    quote bind_quoted: [check: check, key: key, val: val, rhs: rhs] do
      fail = msg(check, "should contain", rhs)
      assert Enum.find(check, false, fn {k, v} -> k == key and v == val end), fail
    end
  end

  defmacro should_contain_key(check, what) do
    quote bind_quoted: [check: check, what: what] do
      fail = msg(check, "should contain key", what)
      assert Enum.find(check, false, fn {k, _v} -> k == what end), fail
    end
  end

  defmacro should_contain_value(check, what) do
    quote bind_quoted: [check: check, what: what] do
      assert Enum.find(check, false, fn
               {_k, v} -> v == what
               v -> v == what
             end),
             msg(check, "should contain value", what)
    end
  end

  defmacro should_contain_binaries(check, binaries) do
    quote bind_quoted: [check: check, binaries: binaries] do
      Should.Be.binary(check)
      Should.Be.list(binaries)

      for x <- binaries do
        Should.Be.binary(x)

        assert String.contains?(check, x), msg(check, "should contain #{x}")
      end
    end
  end

  defmacro should_be_pending(x) do
    quote bind_quoted: [x: x] do
      should_be_status_map(x)
      assert is_map_key(x, :pending), msg(x, "should not have key :pending")
    end
  end

  defmacro should_be_schema(check, schema) do
    quote bind_quoted: [check: check, schema: schema] do
      fail = msg(check, "should be schema", schema)
      assert is_struct(check), fail
      assert check.__struct__ == schema, fail
      assert check.__meta__.schema == schema, fail
      assert check.id, fail
    end
  end

  defmacro should_be_true(check) do
    quote bind_quoted: [check: check] do
      assert check, msg(check, "should be true")
    end
  end

  defmacro should_be_false(check) do
    quote bind_quoted: [check: check] do
      refute check, msg(check, "should be false")
    end
  end

  defmacro should_not_be_pending(x) do
    quote bind_quoted: [x: x] do
      should_be_status_map(x)
      refute is_map_key(x, :pending), msg(x, "should not have key :pending")
    end
  end

  defmacro should_not_be_ttl_expired(x) do
    quote bind_quoted: [x: x] do
      should_be_status_map(x)
      refute is_map_key(x, :ttl_expired), msg(x, "should not have key :ttl_expired")
    end
  end

  defmacro should_be_noreply_tuple_with_state(check, struct) do
    quote bind_quoted: [check: check, struct: struct] do
      fail = msg(check, "should be noreply tuple with state", struct)
      assert is_tuple(check), fail
      assert tuple_size(check) == 2, fail
      assert elem(check, 0) == :noreply, fail
      assert elem(check, 1) |> is_struct(), fail
      assert elem(check, 1).__struct__ == struct, fail
    end
  end

  defmacro should_be_reply_tuple_with_state(check, struct) do
    quote bind_quoted: [check: check, struct: struct] do
      fail = msg(check, "should be reply tuple with", struct)
      should_be_tuple_with_size(check, 3)

      {type, checkults, state} = check

      assert type == :reply, fail
      assert is_struct(state), fail
      assert state.__struct__ == struct, fail

      {checkults, state}
    end
  end

  @doc """
  Converts the passed macro to a string

  ```
  Macro.to_string(macro)
  ```
  """
  defmacro prettym(macro) do
    quote bind_quoted: [macro: macro] do
      Macro.to_string(macro)
    end
  end

  @doc """
  Creates a combined binary of macro and text

  `[Macro.to_string(lhs), text] |> Enum.join(" ")`
  """
  defmacro msg(lhs, text) do
    quote bind_quoted: [lhs: lhs, text: text] do
      lhs_bin = Macro.to_string(lhs)
      [lhs_bin, text] |> Enum.join("\n")
    end
  end

  @doc """
  Creates a combined binary consisting of lhs macro rhs

  `[Macro.to_string(lhs), text, Macro.to_string(rhs)] |> Enum.join(" ")`

  """
  defmacro msg(lhs, text, rhs) do
    quote location: :keep, bind_quoted: [lhs: lhs, text: text, rhs: rhs] do
      lhs_bin = Macro.to_string(lhs)
      rhs_bin = Macro.to_string(rhs)
      [lhs_bin, text, rhs_bin] |> Enum.join("\n")
    end
  end

  @doc "Pretty inspects the passed value"
  def prettyi(x), do: inspect(x, pretty: true)

  @doc "Creates combined binary of msg and the pretty inspection of x"
  def pretty(msg, x) when is_binary(msg) do
    [msg, "\n", prettyi(x)] |> IO.iodata_to_binary()
  end

  @doc "Pretty inspects the passed value and outputs the result"
  defmacro pretty_puts(x) do
    quote bind_quoted: [x: x] do
      ["\n", prettyi(x)] |> IO.puts()

      x
    end
  end

  def pretty_puts_x(x, opts \\ []) when is_map(x) or is_struct(x) do
    struct = struct_name(x)
    map = Map.from_struct(x)
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{only: keys} -> Map.take(map, keys)
      %{exclude: keys} -> Map.drop(map, keys)
      _ -> map
    end
    |> clean_map(opts_map)
    |> then(fn x -> ["\n", struct, inspect(x, pretty: true)] |> IO.puts() end)
    |> then(fn :ok -> x end)
  end

  defp clean_map(x, opts_map) do
    drop_these = Map.take(opts_map, [:structs, :maps, :lists])

    for {what, false} <- drop_these, reduce: x do
      acc ->
        case what do
          :structs -> Enum.reject(acc, fn {_k, val} -> is_struct(val) end)
          :maps -> Enum.reject(acc, fn {_k, val} -> is_map(val) end)
          :lists -> Enum.reject(acc, fn {_k, val} -> is_list(val) end)
        end
    end
  end

  defp struct_name(x) do
    case x do
      x when is_struct(x) -> ["STRUCT: ", Module.split(x.__struct__), "\n"]
      _x -> []
    end
  end
end
