defmodule Sally.Host.Firmware do
  alias File.Stat
  alias Sally.Host
  alias Sally.Host.Instruct

  @file_regex ~r/\d\d\.\d\d\.\d\d.+-ruth\.bin$/
  @default_opts [search_paths: ["."], dir: "firmware", file_regex: @file_regex]
  @config_opts Application.compile_env(:sally, [__MODULE__, :opts], @default_opts)

  @doc false
  def assemble_opts(opts) when is_list(opts) do
    # Sally.Config.get_mod(__MODULE__)
    # Keyword.merge(opts)
    Keyword.merge(@config_opts, opts)
  end

  @doc """
  List of available firmware files

  Examines the `directory` and returns a sorted list of files, in
  descending order, matching specified regex.

  ## Options
  * `:file_regex` - consider matching filenames (default: ~/r.*/)

  ## Returns
  1. `[]` - no files matching `:file_regex` found in `directory`
  2. `[file, ...]` - list of files found, sorted by mtime descending

  ```
  """
  @doc since: "0.5.23"
  def available(directory, opts) when is_binary(directory) and is_list(opts) do
    merged_opts = assemble_opts(opts)

    {file_regex, _} = Keyword.pop(merged_opts, :file_regex, ~r/.*/)

    for file <- files(directory, file_regex), into: [] do
      file_mtime(directory, file)
    end
    # sort descending by mtime
    |> Enum.sort(fn {_, mtime1}, {_, mtime2} -> mtime1 >= mtime2 end)
    # map into a list of binaries
    |> Enum.map(fn {file, _} -> file end)
  end

  @doc """
  Locate the firmware directory

  Searches a list of paths for the directory containing firmware files
  using the options specified.

  ## Options
  * `:search_paths` - list of paths to search (default: `["."]`)
  * `:dir` - directory name to locate (default: `"firmware"`)

  ## Returns
  1. `path` - path of found firmware directory
  2. `{:not_found, :dir}` - unable to locate firmware directory

  ```
  """
  @doc since: "0.5.23"
  def find_dir(opts) when is_list(opts) do
    {search_paths, opts_rest} = Keyword.pop(opts, :search_paths, ["."])
    {dir, _opts_rest} = Keyword.pop(opts_rest, :dir, "firmware")

    Enum.reduce(search_paths, {:not_found, :dir}, fn
      search_path, acc when is_tuple(acc) ->
        path = Path.join(search_path, dir)

        case File.stat(path) do
          {:ok, %Stat{type: :directory, access: x}} when x in [:read, :read_write] -> path
          _ -> acc
        end

      _search_path, acc ->
        acc
    end)
  end

  def ota(:live, opts) when is_list(opts) do
    for %Host{} = host <- Host.live(opts) do
      host |> ota(opts)
    end
  end

  def ota(name, opts) when is_binary(name) and is_list(opts) do
    case Host.find_by(name: name) do
      %Host{} = host -> ota(host, opts)
      nil -> {:not_found, name}
    end
  end

  def ota(%Host{} = host, opts) when is_list(opts) do
    opts_all = assemble_opts(opts)

    {valid_ms, opts_rest} = Keyword.pop(opts_all, :valid_ms, 60_000)
    {want, opts_rest} = Keyword.pop(opts_rest, :want, :latest)

    with dir when is_binary(dir) <- find_dir(opts_rest),
         files when files != [] <- available(dir, opts),
         fw_file when is_binary(fw_file) <- select_file(files, want) do
      # assemble the payload data
      data = %{valid_ms: valid_ms, file: fw_file}

      # create and send the host instruction
      [ident: host.ident, filters: ["ota"], data: data]
      |> Instruct.send()
    else
      {:not_found, :dir} -> {:error, "firmware directory not found"}
      :no_fw_files -> {:error, "no firmware files found"}
      [] -> {:error, "firmware files not available"}
    end
  end

  def select_file(files, want) when is_list(files) do
    cond do
      want == :latest -> 0
      want == :rollback and files != [] -> 1
      is_integer(want) and want < length(files) -> want
      true -> 0
    end
    |> then(fn want -> Enum.at(files, want, :no_fw_files) end)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp files(directory, file_regex) do
    directory
    |> File.ls!()
    |> Enum.filter(fn file -> Regex.match?(file_regex, file) end)
  end

  defp file_mtime(path, file) do
    file_path = Path.join([path, file])

    case File.lstat(file_path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> {file, mtime}
      _ -> []
    end
  end
end
