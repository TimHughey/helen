defmodule Alfred.ExecCmd.Args do
  @moduledoc false

  @remaining_args [:cmd_opts, :cmd_params, :pub_opts]

  def auto(args) when is_list(args) do
    [cmd: make_cmd(args), name: make_name(args)]
    |> get_defaults_and_remaining(args)
    |> merge_all()
    |> prune_spurious_args()
    |> Enum.map(&sort_embedded_lists/1)
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

  @cmd [:cmd, :id]
  @defaults [:cmd_defaults, :defaults]
  @name [:name, :equipment]

  defp defaults(args), do: Keyword.take(args, @defaults) |> pick_first([]) |> map_to_actual()
  defp get_defaults_and_remaining(acc, args), do: {acc, defaults(args), remaining(args)}
  defp make_cmd(args), do: Keyword.take(args, @cmd) |> pick_first() |> to_string()
  defp make_name(args), do: Keyword.take(args, @name) |> pick_first()

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

  defp map_to_actual(args), do: Enum.map(args, &short_key_to_actual/1)

  defp merge_all({acc, defaults, remaining}) do
    Keyword.merge(defaults, acc ++ remaining, &pick_or_merge/3)
  end

  defp pick_first(possible, default \\ :none), do: Keyword.values(possible) |> Enum.at(0, default)

  defp pick_or_merge(key, default, override) do
    case key do
      x when x in [:cmd_params, :cmd_opts, :pub_opts] -> Keyword.merge(default, override)
      x when x in [:cmd, :name] -> override
    end
  end

  @no_params [:off, :on, "off", "on"]
  defp prune_spurious_args(exec_opts) do
    exec_opts_map = Enum.into(exec_opts, %{})

    for {:cmd_params, _val} <- exec_opts_map, reduce: exec_opts_map do
      %{cmd: cmd} = acc when cmd in @no_params -> Map.delete(acc, :cmd_params)
      acc -> acc
    end
    |> Enum.into([])
  end

  defp remaining(args), do: map_to_actual(args) |> Keyword.take(@remaining_args)
  defp short_key_to_actual({:params, val}), do: {:cmd_params, val}
  defp short_key_to_actual({:opts, val}), do: {:cmd_opts, val}
  defp short_key_to_actual(kv), do: kv
  defp sort_embedded_lists({key, val}) when is_list(val), do: {key, Enum.sort(val)}
  defp sort_embedded_lists(kv), do: kv
end
