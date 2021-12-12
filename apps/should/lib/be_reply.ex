defmodule Should.Be.Reply do
  @moduledoc """
  Macros for validating GenServer `{:reply, ...}`
  """

  @doc """
  Asserts when `x` is` {:reply, :ok, struct}`, returns `struct`

  ```
  {reply, rc, struct} = Should.Be.Tuple.with_size(x, 3)
  Should.Be.equal(reply, :reply)
  Should.Be.equal(rc, :ok)
  Should.Be.Struct.with_suffix(struct, State)
  ```

  """
  @doc since: "0.6.22"
  defmacro ok(x) do
    quote location: :keep, bind_quoted: [x: x] do
      {reply, rc, struct} = Should.Be.Tuple.with_size(x, 3)
      Should.Be.equal(reply, :reply)
      Should.Be.equal(rc, :ok)
      Should.Be.Struct.with_suffix(struct, State)
    end
  end

  @doc """
  Asserts when `x` is` {:stop, :normal, reason, struct}`, returns `struct`

  ```
  {reply, reason, rc, struct} = Should.Be.Tuple.with_size(x, 4)
  Should.Be.equal(reply, :stop)
  Should.Be.equal(reason, :normal)
  Should.Be.equal(rc, want_rc)
  Should.Be.Struct.with_suffix(struct, State)
  ```

  """
  @doc since: "0.6.22"
  defmacro stop_normal(x, want_rc) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc] do
      {reply, reason, rc, struct} = Should.Be.Tuple.with_size(x, 4)
      Should.Be.equal(reply, :stop)
      Should.Be.equal(reason, :normal)
      Should.Be.equal(rc, want_rc)
      Should.Be.Struct.with_suffix(struct, State)
    end
  end

  @doc """
  Asserts when `x` is` {:stop, :normal, reason, struct}`, returns `struct`

  ```
  {reply, rc, struct} = Should.Be.Tuple.with_size(x, 4)
  Should.Be.equal(reply, :reply)
  Should.Be.equal(rc, want_rc)
  Should.Be.struct(struct, want_struct)
  ```

  """
  @doc since: "0.6.22"
  defmacro with_rc(x, want_rc) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc] do
      {reply, rc, struct} = Should.Be.Tuple.with_size(x, 4)
      Should.Be.equal(reply, :reply)
      Should.Be.equal(rc, want_rc)
      Should.Be.Struct.with_suffix(struct, State)
    end
  end

  @doc """
  Asserts when `x` is `{:reply, res, struct}`, `struct` is `State`, returns `{res, struct}`

  ```
  {reply, res, struct} = Should.Be.Tuple.with_size(x, 3)
  Should.Be.equal(reply, :reply)

  # returns the reply result and State
  {res, Should.Be.Struct.with_suffix(struct, State)}
  ```

  """
  @doc since: "0.6.26"
  defmacro with_state(x) do
    quote bind_quoted: [x: x] do
      {msg_type, res, state} = Should.Be.Tuple.with_size(x, 3)
      Should.Be.equal(msg_type, :reply)

      assert is_struct(state), Should.msg(state, "should be a struct")

      suffix = state.__struct__ |> Module.split() |> List.last()

      assert suffix == "State", Should.msg(state, "struct should have suffix State")

      # returns the reply result and State
      {res, state}
    end
  end
end
