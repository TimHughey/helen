defmodule Should do
  defmacro __using__(_opts) do
    quote do
      import Should, only: [pretty_puts: 1, pretty: 2]
      require Should.Be
      require Should.Be.{DateTime, Integer, Invalid}
      require Should.Be.{List, Map, NonEmpty, NoReply}
      require Should.Be.{Ok, Reply}
      require Should.Be.{Schema, Server, State, Struct, Tuple, Timer}
      require Should.Contain
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

  defmacro msgt(type, lhs, rhs \\ [], extra \\ []) do
    quote location: :keep, bind_quoted: [type: type, lhs: lhs, rhs: rhs, extra: extra] do
      lhs = Macro.to_string(lhs)
      rhs = if(rhs != [], do: Macro.to_string(rhs), else: rhs)

      type_msg = Should.type_to_msg(type)
      text = if(extra != [], do: "#{type_msg} (#{extra})", else: type_msg)

      [lhs, text, rhs] |> Enum.join("\n")
    end
  end

  @doc "Pretty inspects the passed value"
  def prettyi(x), do: inspect(x, pretty: true)

  @doc "Creates combined binary of msg and the pretty inspection of x"
  def pretty(msg, x) when is_binary(msg) do
    [msg, "\n", prettyi(x)] |> IO.iodata_to_binary()
  end

  @doc """
  Inspect pretty `x`, send to `IO.puts/1` and pass through `x`

  ```
  IO.puts(["\n", prettyi(x)])
  |> then(fn :ok -> x end)
  ```
  """
  defmacro pretty_puts(x) do
    quote bind_quoted: [x: x] do
      IO.puts(["\n", inspect(x, pretty: true)])
      |> then(fn :ok -> x end)
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

  def type_to_msg(type) do
    case type do
      t when is_nil(t) -> "should be nil"
      :atom -> "should be an atom"
      :binary -> "should be a binary"
      :datetime -> "should be a DateTime"
      :integer -> "should be an integer"
      :list -> "should be a list"
      :map -> "should be a map"
      :pid -> "should be pid"
      {:pid, :alive} -> "should be an alive pid"
      :struct -> "should be struct"
      {:struct, name} -> "should be struct named #{name}"
      :tuple -> "should be a tuple"
      {:tuple, size} -> "should be a tuple with size #{size}"
      :reference -> "should be a reference"
    end
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
