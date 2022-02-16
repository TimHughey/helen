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

  @doc """
  Create a unique equipment name for merge into a test `Exunit` test context.

  When context contains`%{equipment_add: opts}` returns `%{equipment: "name"}`.
  Otherwise returns `:ok`.

  This is a specialized function for creating a mutable name.

  See `Alfred.NamesAid.name_add/1` for available options.

  """
  # NOTE: need ctx for ref_dt/0
  def equipment_add(%{equipment_add: opts}) do
    dev_alias = new_dev_alias(:equipment, opts)

    name = if(match?(%Alfred.DevAlias{}, dev_alias), do: dev_alias.name, else: "unknown")

    %{equipment: name, dev_alias: dev_alias}
  end

  def equipment_add(_), do: :ok

  def new_dev_alias(type, opts) do
    {parts_opts, opts_rest} = split_parts_opts(opts)

    case type do
      :equipment -> binary_from_opts(:mut, parts_opts)
      :sensor -> binary_from_opts(:imm, parts_opts)
    end
    |> Alfred.DevAlias.new(opts_rest)
  end

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
        {type, opts_rest} = Keyword.pop(opts, :type, :name)
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

  def parts_auto_add(ctx) do
    case ctx do
      %{name: name} -> %{parts_add: name}
      _ -> :ok
    end
  end

  @sensor_default [rc: :ok, temp_f: 81.1]
  def sensor_add(%{sensor_add: opts}) do
    opts = Keyword.merge(@sensor_default, opts)

    dev_alias = new_dev_alias(:sensor, opts)

    %{sensor: dev_alias.name, dev_alias: dev_alias}
  end

  def sensor_add(_), do: :ok

  @default_temp_f [11.0, 11.1, 11.2, 6.2]
  def sensors_add(%{sensors_add: []}) do
    default_opts = Enum.map(@default_temp_f, fn temp_f -> [temp_f: temp_f] end)

    %{sensors_add: default_opts}
    |> sensors_add()
  end

  def sensors_add(%{sensors_add: [_ | _] = many}) do
    dev_aliases = Enum.map(many, &new_dev_alias(:sensor, &1))

    %{sensors: Enum.map(dev_aliases, &Map.get(&1, :name)), dev_alias: dev_aliases}
  end

  def sensors_add(_ctx), do: :ok

  ##
  ## Binary conversions - from opts and to_parts
  ##

  @parts_opts [:busy, :cmd, :expired_ms, :name, :rc, :relhum, :temp_f, :timeout, :ttl_ms, :type]
  # @parts_opts [:busy, :cmd, :expired_ms, :name, :rc, :timeout, :ttl_ms, :type]
  def parts_opts, do: @parts_opts

  def split_parts_opts(opts), do: Keyword.split(opts, @parts_opts)

  def binary_from_opts(type, opts) when is_list(opts) do
    opts_map = Enum.into(opts, %{})

    case type do
      :name when is_map_key(opts_map, :prefix) -> unique(opts_map.prefix)
      x when x in [:imm, :immutable] -> immutable(opts_map)
      x when x in [:mut, :mutable] -> mutable(opts_map)
      x when x in [:unk, :unknown] -> unknown(opts_map)
    end
  end

  def binary_to_parts(name) when is_binary(name) do
    case regex_common(name) do
      %{type: :mut, args: args} = x -> {regex_mutable(args), x}
      %{type: :imm, args: args} = x -> {regex_immutable(args), x}
      %{type: :unk} = x -> {%{rc: :unknown}, x}
    end
    |> merge_and_clean()
  end

  ##
  ## Misc
  ##

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
      #  %{cmd: :random} -> random_cmd(12)
      %{cmd: cmd} -> cmd
      _ -> random_cmd(12)
    end
  end

  @data_error [:expired, :error]
  defp add_data(opts_map) do
    # must ensure temp_f always proceeds relhum
    data = Map.take(opts_map, [:temp_f, :relhum]) |> Enum.into([]) |> Enum.sort()

    case opts_map do
      %{rc: :ok} when data == [] -> raise("must provide data for immutable")
      %{rc: rc} when rc in @data_error -> make_daps(temp_f: 0.0)
      _ -> make_daps(data)
    end

    # # sort the list first so relhum is before temp_f
    # # the for loop will then create the data elements list in reverse order
    # # so temp_f is before relhum
    # for {k, v} <- Enum.sort(data, fn {_, lhs}, {_, rhs} -> lhs >= rhs end) do
    #   [Atom.to_string(k), Float.to_string(v * 1.0)] |> Enum.join("=")
    # end
    # |> Enum.join(" ")
  end

  defp add_rc(opts_map) do
    case opts_map do
      %{expired_ms: _} -> "expired"
      %{busy: true} -> "busy"
      %{timeout: true} -> "timeout"
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

  def make_daps(data) do
    Enum.map(data, fn {key, val} ->
      [Atom.to_string(key), "=", Float.to_string(val * 1.0)] |> IO.iodata_to_binary()
    end)
    |> Enum.join(" ")
  end

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

  def random_cmd(length \\ 8), do: Enum.take_random(?a..?z, length) |> to_string()

  defp regex_common(name) when is_binary(name) do
    re = ~r/^
      ((?<type>imm|mut|unk)[a-z0-9_]+)\s
      (?<rc>[a-z]+)\s?
      (?<args>.+)?
      $/x

    case Regex.named_captures(re, name) do
      x when is_nil(x) -> raise(~s(parse failed: "name"))
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
      x when is_nil(x) -> raise(~s(parse failed: "name"))
      x when is_map(x) -> make_matchable(x)
    end
  end

  defp regex_mutable(args) when is_binary(args) do
    re = ~r/^
      (?<cmd>[a-z0-9_]+)\s?
      (expired_ms=(?<expired_ms>[0-9]+))?
      $/x

    case Regex.named_captures(re, args) do
      x when is_nil(x) -> raise(~s(parse failed: "name"))
      x when is_map(x) -> make_matchable(x)
    end
  end

  defp to_binary(x), do: x |> Enum.reject(fn x -> is_nil(x) end) |> Enum.join(" ")

  defp to_float_safe(x) do
    case Float.parse(x) do
      {val, _} -> val
      :error -> raise("unable to convert #{inspect(x)} to float")
    end
  end
end
