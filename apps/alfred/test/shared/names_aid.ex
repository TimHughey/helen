defmodule Alfred.NamesAid do
  @moduledoc """
  Create unique binary name and split a binary name into a map of parts

  ## Introduction

  Development and testing of apps that interact with `Alfred` often must
  create a number of unique names that are passed to various functions
  (e.g. `Alfred.just_saw/2`, `Alfred.execute/2`, `Alfred.status/2`,
  `Alfred.notify_register/1`)

  """

  alias Alfred.{JustSaw, SeenName}

  @type seen_name_opts() :: [name: String.t(), seen_at: %DateTime{}, ttl_ms: integer()]

  @type ctx_map :: %{
          optional(:make_name) => name_opts(),
          optional(:make_parts) => String.t(),
          optional(:seen_name) => seen_name_opts(),
          optional(:name) => String.t()
        }

  @doc "Submits the name in the ctx via Alfred.JustSaw"
  @callback just_saw(ctx_map) :: %{optional(:just_saw_result) => [String.t(), ...]}

  @doc "Makes a name for a test context"

  @callback make_name(ctx_map) :: %{optional(:name) => String.t()} | :ok
  @callback make_parts(ctx_map) :: %{optional(:parts) => name_parts_map()} | :ok
  @callback make_parts_auto(ctx_map) :: %{optional(:name) => String.t()} | :ok
  @callback make_seen_name(ctx_map) :: %{optional(:seen_name) => %SeenName{}}

  @doc "Creates a unique name of specified type using passed opts"
  @type name_type :: :imm | :mut | :unk
  @type name_rc :: :ok | :pending | :error | :unknown
  @type name_opts :: [rc: name_rc, cmd: String.t(), expired_ms: integer(), temp_f: float(), relhum: float()]
  @callback name_from_opts(type :: atom(), opts :: name_opts()) :: binary()

  @doc "Creates a map of the parts of a created unique name"
  @type name_parts_map() :: %{
          :name => binary(),
          :rc => name_rc(),
          optional(:cmd) => binary(),
          optional(:expired_ms) => integer(),
          optional(:temp_f) => float(),
          optional(:relhum) => float()
        }
  @callback name_to_parts(name :: binary()) :: name_parts_map()

  @doc "Creates a unique name with the specified prefix"
  @callback unique_with_prefix(prefix :: binary(), index :: integer()) :: binary()

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Alfred.NamesAid

      alias Alfred.NamesAid

      def just_saw(ctx), do: NamesAid.just_saw(ctx)
      def make_name(ctx), do: NamesAid.make_name(ctx)
      def make_parts(ctx), do: NamesAid.make_parts(ctx)
      def make_parts_auto(ctx), do: NamesAid.make_parts_auto(ctx)
      def make_seen_name(ctx), do: NamesAid.make_seen_name(ctx)

      def name_from_opts(type, opts)
          when is_atom(type)
          when is_list(opts)
          when opts != [] do
        Alfred.NamesAid.from_opts(type, opts)
      end

      def name_to_parts(name)
          when is_binary(name) do
        Alfred.NamesAid.to_parts(name)
      end

      def unique_with_prefix(prefix, index \\ 4)
          when is_binary(prefix)
          when is_integer(index)
          when index >= 0 and index <= 4 do
        Alfred.NamesAid.unique(prefix, index)
      end
    end
  end

  def from_opts(type, opts) when is_list(opts) do
    opts_map = Enum.into(opts, %{})

    case type do
      x when x in [:imm, :immutable] -> immutable(opts_map)
      x when x in [:mut, :mutable] -> mutable(opts_map)
      x when x in [:unk, :unknown] -> unknown(opts_map)
    end
  end

  def just_saw(ctx) do
    case ctx do
      %{seen_name: sn, parts: parts, just_saw: opts} when is_list(opts) ->
        cb = opts[:callback] || {:module, __MODULE__}
        mut? = parts.type == :mut

        js = %JustSaw{mutable?: mut?, callback: cb, seen_list: [sn]}

        %{just_saw: js, just_saw_result: Alfred.just_saw(js)}

      _ ->
        :ok
    end
  end

  def make_seen_name(ctx) do
    case ctx do
      %{name: name, parts: parts} ->
        expired_ms = (parts[:expired_ms] || 0) * -1
        ttl_ms = parts[:ttl_ms] || 5_000
        seen_at = DateTime.utc_now() |> DateTime.add(expired_ms)
        %{seen_name: %SeenName{name: name, seen_at: seen_at, ttl_ms: ttl_ms}}

      _ ->
        :ok
    end
  end

  def make_name(ctx) do
    case ctx do
      %{make_name: opts} ->
        {type, opts_rest} = Keyword.pop(opts, :type)
        {key, opts_rest} = Keyword.pop(opts_rest, :key, :name)

        %{key => from_opts(type, opts_rest)}

      _ ->
        :ok
    end
  end

  def make_parts(ctx) do
    case ctx do
      %{make_parts: name} -> %{parts: to_parts(name)}
      _ -> :ok
    end
  end

  def make_parts_auto(ctx) do
    case ctx do
      %{name: name} -> %{make_parts: name}
      _ -> :ok
    end
  end

  def to_parts(name) when is_binary(name) do
    case regex_common(name) do
      %{type: :mut, args: args} = x -> regex_mutable(args) |> merge_and_clean(x)
      %{type: :imm, args: args} = x -> regex_immutable(args) |> merge_and_clean(x)
      %{type: :unk} = x -> %{rc: :unkown} |> Map.merge(x)
    end
  end

  def unique(prefix, index \\ 4)
      when is_binary(prefix)
      when is_integer(index)
      when index >= 0 and index <= 4 do
    index = if(is_integer(index), do: index, else: 4)

    serial = Ecto.UUID.generate() |> String.split("-") |> Enum.at(index)

    [prefix, "_", serial] |> IO.iodata_to_binary()
  end

  ##
  ## Private
  ##

  defp merge_and_clean(m1, m2) do
    Map.merge(m1, m2) |> Map.drop([:args])
  end

  defp immutable(opts_map) do
    [unique("immutable"), add_rc(opts_map), add_expired(opts_map), add_data(opts_map)] |> to_binary()
  end

  defp mutable(opts_map) do
    [unique("mutable"), add_rc(opts_map), add_cmd(opts_map), add_expired(opts_map)] |> to_binary()
  end

  defp unknown(_opts) do
    [unique("unknown"), "unknown"] |> to_binary()
  end

  ## populate specific parts of name

  defp add_cmd(opts_map) do
    case opts_map do
      %{cmd: cmd} -> cmd
      _ -> "off"
    end
  end

  defp add_data(opts_map) do
    # must ensure temp_f always proceeds relhum
    data = Map.take(opts_map, [:temp_f, :relhum]) |> Enum.into([])

    # sort the list first so relhum is before temp_f
    # the for loop will then create the data elements list in reverse order
    # so temp_f is before relhum
    for {k, v} <- Enum.sort(data, fn {_, lhs}, {_, rhs} -> lhs >= rhs end) do
      [Atom.to_string(k), Float.to_string(v * 1.0)] |> Enum.join("=")
    end
    |> Enum.join(" ")
  end

  defp add_rc(opts_map) do
    case opts_map do
      %{expired_ms: _} -> "expired"
      %{pending: true} -> "pending"
      %{rc: rc} when is_atom(rc) -> Atom.to_string(rc)
      %{rc: rc} when is_binary(rc) -> rc
      _ -> "ok"
    end
  end

  defp add_expired(opts_map) do
    case opts_map do
      %{expired_ms: val} -> "expired_ms=#{val}"
      _ -> nil
    end
  end

  ## general support

  defp make_matchable(map) when is_map(map) do
    for {k, v} when v != "" <- map, into: %{} do
      case {k, v} do
        {"rc", rc} -> {:rc, String.to_atom(rc)}
        {"type", type} -> {:type, String.to_atom(type)}
        {"cmd", cmd} -> {:cmd, cmd}
        {"expired_ms", x} -> {:expired_ms, String.to_integer(x)}
        {"temp_f", x} -> {:temp_f, to_float_safe(x)}
        {"relhum", x} -> {:relhum, to_float_safe(x)}
        {k, v} when is_binary(k) -> {String.to_atom(k), v}
      end
    end
  end

  defp regex_common(name) when is_binary(name) do
    re = ~r/^
      ((?<type>imm|mut|unk)[a-z0-9_]+)\s
      (?<rc>[a-z]+)\s?
      (?<args>.+)?
      $/x

    case Regex.named_captures(re, name) do
      x when is_nil(x) -> %{name: name, parse_failed: :common}
      x when is_map(x) -> make_matchable(x) |> Map.put(:name, name)
    end
  end

  defp regex_immutable(args) when is_binary(args) do
    re = ~r/^
      (temp_f=(?<temp_f>[0-9]+[.]?[0-9]*))
      (\s?relhum=(?<relhum>[0-9]+[.]?[0-9]*))?
      (\s?expired_ms=(?<expired_ms>[0-9]+))?
      $/x

    case Regex.named_captures(re, args) do
      x when is_nil(x) -> %{parse_failed: :immutable}
      x when is_map(x) -> make_matchable(x)
    end
  end

  defp regex_mutable(args) when is_binary(args) do
    re = ~r/^
      (?<cmd>[a-z0-9_]+)\s?
      (expired_ms=(?<expired_ms>[0-9]+))?
      $/x

    case Regex.named_captures(re, args) do
      x when is_nil(x) -> %{parse_failed: :mutable}
      x when is_map(x) -> make_matchable(x)
    end
  end

  defp to_binary(x) do
    x |> Enum.reject(fn x -> is_nil(x) end) |> Enum.join(" ")
  end

  defp to_float_safe(x) do
    case Float.parse(x) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
