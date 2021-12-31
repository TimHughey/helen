defmodule Alfred.ExecCmd.Args do
  @moduledoc false

  def auto({args, defaults}), do: auto(args, defaults)

  @auto_merge [:cmd_opts, :cmd_params, :pub_opts]
  @select_first [:name, :cmd]
  @cmd_opts_short [:ack, :echo, :force, :notify]
  def auto(args, defaults) when is_list(args) and is_list(defaults) do
    args = map_short_keys(args)
    defaults = map_short_keys(defaults)

    base = %{cmd_opts: [], cmd_params: [], pub_opts: []}

    # make a single list of specified args first and defaults second
    # so the reduction finds specific args first
    for {key, value} <- args ++ defaults, reduce: base do
      # always merge :cmd_opts, :cmd_params and :pub_opts
      acc when key in @auto_merge -> merge_and_put(acc, key, value)
      # use the first :cmd and :name found
      acc when key in @select_first -> select_first(acc, key, value)
      # alternates for name
      acc when key == :equipment -> select_first(acc, :name, value)
      # alternates for cmd
      acc when key == :id -> select_first(acc, :cmd, value)
      acc when key in @cmd_opts_short -> cmd_opts_merge(acc, key, value)
      # ignore unknown keys
      acc -> acc
    end
    |> Enum.into([])
    |> Enum.map(fn kv -> sort_embedded_lists(kv) end)
    |> Enum.sort()
  end

  def version_cmd(cmd) when is_binary(cmd) do
    [cmd: cmd] |> version_cmd() |> Keyword.get(:cmd)
  end

  def version_cmd(args) when is_list(args) do
    args_map = Enum.into(args, %{})

    case args_map do
      %{cmd: x} when x in ["on", "off"] -> args_map
      %{cmd: x} when is_binary(x) -> %{args_map | cmd: make_version(x)}
      %{cmd: x} when is_atom(x) -> args_map
      _cmd_missing -> args_map
    end
    |> Enum.into([])
  end

  def version_cmd(x), do: x

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def cmd_opts_merge(acc, key, value) do
    cmd_opts = Map.get(acc, :cmd_opts)

    case key do
      :notify -> Keyword.put_new(cmd_opts, :notify_when_released, value)
      _ -> Keyword.put_new(cmd_opts, key, value)
    end
    |> then(fn cmd_opts -> Map.put(acc, :cmd_opts, cmd_opts) end)
  end

  @version_split ~r/(?: v(?=\d{3}$))/
  defp make_version(x) do
    try do
      [prefix, version] = Regex.split(@version_split, x)
      next_version = (String.to_integer(version) + 1) |> to_string() |> String.pad_leading(3, "0")

      [prefix, "v#{next_version}"]
    rescue
      [MatchError, ArgumentError, ArithmeticError] ->
        [x, "v001"]
    end
    |> Enum.join(" ")
  end

  defp map_short_keys(args), do: Enum.map(args, &short_key_to_actual/1)

  defp merge_and_put(acc, key, defaults) do
    Map.get(acc, key)
    |> then(fn priority -> Keyword.merge(defaults, priority) end)
    |> then(fn merged -> Map.put(acc, key, merged) end)
  end

  defp short_key_to_actual({:params, val}), do: {:cmd_params, val}
  defp short_key_to_actual({:opts, val}), do: {:cmd_opts, val}
  defp short_key_to_actual(kv), do: kv

  defp select_first(acc, key, value) when is_atom(value), do: select_first(acc, key, to_string(value))
  defp select_first(acc, key, value) when not is_map_key(acc, key), do: Map.put(acc, key, value)
  defp select_first(acc, _key, _value), do: acc

  defp sort_embedded_lists({key, val}) when is_list(val), do: {key, Enum.sort(val)}
  defp sort_embedded_lists(kv), do: kv
end
