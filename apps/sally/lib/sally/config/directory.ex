defmodule Sally.Config.Directory do
  @moduledoc false

  def discover({mod, key} = _what) do
    mod_config = Sally.Config.Agent.config_get({mod, key})
    {dir, rest} = Keyword.pop(mod_config, :dir, :auto)
    {search_paths, _} = Keyword.pop(rest, :search_paths, ["."])

    case dir do
      :auto -> to_string(key)
      <<_::binary>> -> dir
      _ -> :none
    end
    |> search(search_paths)
  end

  def search(<<_::binary>> = dir, search_paths) when is_list(search_paths) do
    Enum.reduce(search_paths, :none, fn
      # directory parh not found yet
      search_path, :none ->
        path_parts = [search_path, dir]

        case search_path do
          # absolute search path
          <<"/"::binary, _rest::binary>> -> path_parts
          # relative search path
          <<_::binary>> -> [File.cwd!() | path_parts]
        end
        |> check_path()

      # directory path found
      _search_path, acc ->
        acc
    end)
  end

  def search(_, _), do: :none

  def check_path(path_parts) do
    path = Path.join(path_parts)

    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{type: :directory, access: x}} when x in [:read, :read_write] -> path
      _x -> :none
    end
  end
end
