defmodule Alfred.NamesAid do
  @moduledoc """
  Create unique binary name and split a binary name into a map of parts

  ## Introduction

  Development and testing of apps that interact with `Alfred` often must
  create a number of unique names that are passed to various functions
  (e.g. `Alfred.just_saw/2`, `Alfred.execute/2`, `Alfred.status/2`,
  `Alfred.notify_register/1`)

  """

  ##
  ## ExUnit setup functions
  ##

  defmacrop ref_dt do
    quote do: Map.get(var!(ctx), :ref_dt, Timex.now("America/New_York"))
  end

  @doc """
  Create a unique equipment name for merge into a test `Exunit` test context.

  When context contains`%{equipment_add: opts}` returns `%{equipment: "name"}`.
  Otherwise returns `:ok`.

  This is a specialized function for creating a mutable name.

  See `Alfred.NamesAid.name_add/1` for available options.

  """
  # NOTE: need ctx for ref_dt/0
  def equipment_add(%{equipment_add: opts} = ctx) do
    {register_opts, opts_rest} = Keyword.pop(opts, :register, [])
    register_opts = Alfred.Name.register_opts(register_opts, seen_at: ref_dt())

    name = binary_from_opts(:mut, opts_rest)

    dev_alias = Alfred.Test.DevAlias.new(name)
    rc = Alfred.Test.DevAlias.register(dev_alias, register_opts)

    %{equipment: name, registered_name: %{dev_alias: dev_alias, name: name, rc: rc}}
  end

  def equipment_add(_), do: :ok

  @doc """
  Create a unique name of type for merge into `ExUnit` test context.

  ## Examples
  ```
  # create an unknown name
  %{name: "unknown_71ceb180f436 unknown"} = NamesAid.name_add(%{name_add: [type: :unk]})

  # create a mutable name with cmd: "on"
  opts = [type: :mut, cmd: "on"]
  %{name: "mutable_4e03ab01ad2a ok on"} = NamesAid.name_add(%{name_add: opts]})
  ```

  ## Options

  | Key  | Values | Description | Comment |
  | -----| ------ | ----------- | ------- |
  | `type:`  | `:imm`, `:mut`, `:unk`  | immutable, mutable or unknown | default: `:imm` |
  | `key:` | `any()` | map key of created name | default: `name:` |


  ## Options
  * `:type` - create `:imm` immutable,  `:mut` mutable or `:unk` unknown name
  * `:key` - key of created name in returned map (i.e. `%{key => name}`), defaults to :name

  """
  def name_add(ctx) do
    case ctx do
      %{name_add: opts} ->
        {type, opts_rest} = Keyword.pop(opts, :type)
        {key, opts_rest} = Keyword.pop(opts_rest, :key, :name)

        %{key => binary_from_opts(type, opts_rest)}

      _ ->
        :ok
    end
  end

  def parts_add(ctx) do
    case ctx do
      %{parts_add: name} -> %{parts: binary_to_parts(name)}
      _ -> :ok
    end
  end

  def parts_add_auto(ctx) do
    case ctx do
      %{name: name} -> %{parts_add: name}
      _ -> :ok
    end
  end

  def sensor_add(%{sensor_add: opts} = ctx) do
    {register_opts, opts_rest} = Keyword.pop(opts, :register, [])
    register_opts = Alfred.Name.register_opts(register_opts, seen_at: ref_dt())

    name = binary_from_opts(:imm, opts_rest)

    dev_alias = Alfred.Test.DevAlias.new(name)
    rc = Alfred.Test.DevAlias.register(name, register_opts)

    %{sensor: name, registered_name: %{dev_alias: dev_alias, name: name, rc: rc}}
  end

  def sensor_add(_), do: :ok

  @default_temp_f [11.0, 11.1, 11.2, 6.2]
  def sensors_add(%{sensors_add: []}) do
    default_opts = Enum.map(@default_temp_f, fn temp_f -> [temp_f: temp_f] end)

    %{sensors_add: default_opts}
    |> sensors_add()
  end

  def sensors_add(%{sensors_add: [_ | _] = many} = ctx) do
    Enum.reduce(many, %{register: [seen_at: ref_dt()], sensors: []}, fn
      [{:register = key, val}], acc ->
        Map.put(acc, key, val)

      [_ | _] = opts, %{register: register_opts, sensors: sensors} = acc ->
        name = binary_from_opts(:imm, opts)

        register_opts = Alfred.Name.register_opts(register_opts, seen_at: ref_dt())
        Alfred.Test.DevAlias.register(name, register_opts)

        Map.put(acc, :sensors, [name | sensors])

      _, acc ->
        acc
    end)
  end

  def sensors_add(_ctx), do: :ok

  ##
  ## Binary conversions - from opts and to_parts
  ##

  def binary_from_opts(type, opts) when is_list(opts) do
    opts_map = Enum.into(opts, %{})

    case type do
      x when x in [:imm, :immutable] -> immutable(opts_map)
      x when x in [:mut, :mutable] -> mutable(opts_map)
      x when x in [:unk, :unknown] -> unknown(opts_map)
    end
  end

  def binary_to_parts(name) when is_binary(name) do
    case regex_common(name) do
      %{type: :mut, args: args} = x -> {regex_mutable(args), x}
      %{type: :imm, args: args} = x -> {regex_immutable(args), x}
      %{type: :unk} = x -> {%{rc: :unkown}, x}
    end
    |> merge_and_clean()
  end

  ##
  ## Misc
  ##

  def possible_parts do
    # NOTE: the order of part keys is significant for assembling an
    # accurate view of a binary name.  e.g. expired_ms is used to
    # create updated_at.
    [:name, :expired_ms, :type, :rc, :ttl_ms, :cmd, :temp_f, :relhum]
  end

  def unique(prefix, index \\ 4)
      when is_binary(prefix)
      when is_integer(index)
      when index >= 0 and index <= 4 do
    index = if(is_integer(index), do: index, else: 4)

    serial = UUID.uuid4() |> String.split("-") |> Enum.at(index)

    [prefix, "_", serial] |> IO.iodata_to_binary()
  end

  ##
  ## Private
  ##

  defp merge_and_clean({m1, m2}), do: Map.merge(m1, m2) |> Map.drop([:args])

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
      %{orphaned: true} -> "orphaned"
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
