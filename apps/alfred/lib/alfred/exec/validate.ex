defmodule Alfred.ExecCmd.Validate do
  # def args_list(args) when is_list(args), do: check
  #
  # ## PRIVATE
  # ## PRIVATE
  # ## PRIVATE
  #
  # defp check(args_map, {:stop, reason}) do
  #   args_map
  #   |> Map.put(:invalid_reason, reason)
  #   |> Enum.into([])
  #   |> Enum.sort()
  # end
  #
  # defp check(args, :start), do: Enum.into(args, %{}) |> name()
  #
  # defp name(%{name: <<_x::binary-size(1), _rest::binary>>} = x, :ok), do: check(x, :ok)
  # defp check(%{name: :none} = x, :ok), do: check(x, {:stop, "name is missing"})
end
