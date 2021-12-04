defmodule Should.Be.NoReply do
  @moduledoc """
  Macros for validating GenServer `{:noreply, ...}`
  """

  @doc """
  Asserts when `x` is` {:stop, reason, struct}`, returns `struct`

  ```
  {reply, reason, struct} = Should.Be.Tuple.with_size(x, 3)
  Should.Be.equal(reply, :stop)
  Should.Be.equal(reason, want_reason)
  Should.Be.Struct.with_suffix(struct, State)
  ```

  """
  @doc since: "0.6.22"
  defmacro stop(x, want_reason) do
    quote location: :keep, bind_quoted: [x: x, want_reason: want_reason] do
      {reply, reason, struct} = Should.Be.Tuple.with_size(x, 3)
      Should.Be.equal(reply, :stop)
      Should.Be.equal(reason, want_reason)
      Should.Be.Struct.with_suffix(struct, State)
    end
  end

  @doc """
  Asserts when `x` is` {:noreply, %State{}}`, returns `struct`

  ```
  {reply, struct} = Should.Be.Tuple.with_size(x, 2)
  Should.Be.equal(reply, :noreply)
  Should.Be.struct(struct, want_struct)
  ```

  """
  @doc since: "0.6.22"
  defmacro with_state(x) do
    quote location: :keep, bind_quoted: [x: x] do
      {reply, struct} = Should.Be.Tuple.with_size(x, 2)
      Should.Be.equal(reply, :noreply)
      Should.Be.Struct.with_suffix(struct, State)
    end
  end

  @doc """
  Asserts when `x` is` {:noreply, struct}`, returns `struct`

  ```
  {reply, struct} = Should.Be.Tuple.with_size(x, 2)
  Should.Be.equal(reply, :noreply)
  Should.Be.struct(struct, want_struct)
  ```

  """
  @doc since: "0.6.22"
  defmacro with_struct(x, want_struct) do
    quote location: :keep, bind_quoted: [x: x, want_struct: want_struct] do
      {reply, struct} = Should.Be.Tuple.with_size(x, 2)
      Should.Be.equal(reply, :noreply)
      Should.Be.struct(struct, want_struct)
    end
  end
end
