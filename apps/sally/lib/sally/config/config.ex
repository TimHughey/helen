defmodule Sally.Config do
  @moduledoc """
  Sally Runtime configuration API
  """

  use Agent

  @search :search
  @state_base %{cache: %{paths: %{}}}
  @cache_paths [:cache, :paths]
  def start_link(args) do
    {server_name, args_rest} = Keyword.pop(args, :name, __MODULE__)
    app = Application.get_application(__MODULE__)

    case args_rest do
      # when args rest is empty grab configuration from Application env
      [] -> Application.get_all_env(app)
      # otherwise use the passed args
      [_ | _] -> args_rest
      # when no match use empty config,
      _ -> []
    end
    # make a map from config list
    |> Enum.into(%{})
    # make the state including the config map
    |> then(fn config_map -> Map.put(@state_base, :config, config_map) end)
    # start the Agent with the assembled state
    |> then(fn state -> Agent.start_link(fn -> state end, name: server_name) end)
  end

  ##
  ## Generic Config Key/Value Access
  ##

  def get_via_path([_ | _] = path, default \\ nil) do
    path = [:config | path]
    val = Agent.get(__MODULE__, &get_in(&1, path))

    if val, do: val, else: default
  end

  ##
  ## Macros for reduce_while
  ##

  defmacrop cmap_cont(chk_map) do
    quote bind_quoted: [chk_map: chk_map], do: {:cont, chk_map}
  end

  defmacrop cmap_merge(map, :no_tuple = action) do
    quote bind_quoted: [map: map, action: action] do
      chk_map = var!(chk_map) |> Map.merge(map)

      if action == :cont, do: {:cont, chk_map}, else: chk_map
    end
  end

  defmacrop cmap_put(val, action \\ :cont) do
    quote bind_quoted: [val: val, action: action] do
      chk_map = var!(chk_map)
      key = var!(key)

      chk_map = put_in(chk_map, [key], val)

      if action == :cont, do: {:cont, chk_map}, else: chk_map
    end
  end

  ##
  ## File in path
  ##

  @locate_steps [:path, :found, :files, :select, :return]
  @locate_path_error {:error, :no_path}
  def file_locate({mod, key} = what, opts \\ []) do
    state = Agent.get(__MODULE__, & &1)
    config = get_in(state, [:config, mod, key]) || []
    config = Keyword.merge(config, opts)
    regex = Keyword.get(config, :file_regex, ~r/.*/)

    chk_map = %{config: config, opts: opts, regex: regex}

    Enum.reduce_while(@locate_steps, chk_map, fn
      :path = key, chk_map -> path_get(what, state: state) |> cmap_put()
      :found = key, %{path: <<_::binary>>} = chk_map -> cmap_put(:yes)
      :found, _chk_map -> {:halt, @locate_path_error}
      :files = key, chk_map -> files_filter(chk_map, key)
      :select = key, chk_map -> files_select(chk_map, key)
      :return, %{select: :chk_map} -> {:halt, chk_map}
      :return, %{select: selected} -> {:halt, selected}
    end)
  end

  @access_want [:read, :read_write]
  @file_type :regular
  @stat_opts [time: :posix]
  @doc false
  def files_filter(%{path: path, regex: regex} = chk_map, key) do
    files = File.ls!(path)

    Enum.reduce(files, [], fn file, acc ->
      # NOTE: && is a short-circuit operator so File.stat/2 is only executed if the regex matches
      stat_rc = Regex.match?(regex, file) && File.stat(Path.join([path, file]), @stat_opts)

      # accumulate a list of {mtime, file} tuples for regular files we can at least read
      case stat_rc do
        {:ok, %{access: x, type: @file_type, mtime: mtime}} when x in @access_want -> [{mtime, file} | acc]
        _ -> acc
      end
    end)
    # NOTE: erlang term ordering handles {mtime, file} tuples, use >= for newest file first
    |> Enum.sort(&(&1 >= &2))
    # detuple to just the file name
    |> Enum.map(&elem(&1, 1))
    |> cmap_put()
  end

  @nofile :no_file
  @want_default :path_files
  @files_opts_error """
  want option must be one of the following (or unset):
   :latest, :previous, :path_files, :chk_map or an integer index of list of files
  """
  def files_select(%{files: files, opts: opts} = chk_map, key) do
    want = opts[:want] || @want_default

    cond do
      want == :latest -> Enum.at(files, 0, @nofile)
      want == :previous -> Enum.at(files, 1, @nofile)
      is_integer(want) -> Enum.at(files, want, @nofile)
      want == :path_files -> {chk_map.path, chk_map.files}
      want == :chk_map -> want
      true -> raise(@files_opts_error)
    end
    |> cmap_put()
  end

  ##
  ## Filesystem Paths
  ##

  @doc false
  def path_cache(%{found: found, paths: cached_paths} = chk_map, key) do
    case found do
      <<_::binary>> ->
        cached_paths = Map.put(cached_paths, key, found)

        Agent.update(__MODULE__, &put_in(&1, @cache_paths, cached_paths))

        key = :paths
        cmap_put(cached_paths)

      _ ->
        cmap_cont(chk_map)
    end
  end

  @path_get_steps [:cache_hit, :path_find, :cache, :return]
  @doc since: "0.7.14"
  def path_get({mod, key} = what, opts \\ []) when is_atom(mod) and is_atom(key) do
    state = opts[:state] || Agent.get(__MODULE__, & &1)
    config = get_in(state, [:config, mod]) || []
    cached_paths = get_in(state, @cache_paths)
    chk_map? = Keyword.get(opts, :chk_map, false)

    chk_map = %{config: config, paths: cached_paths}

    Enum.reduce_while(@path_get_steps, chk_map, fn
      :cache_hit, %{paths: %{^what => path}} -> {:halt, path}
      # NOTE: the remaining steps are skipped when cache hit
      :cache_hit = key, chk_map -> cmap_put(:no)
      :path_find, chk_map -> path_find(chk_map, what)
      :cache, chk_map -> path_cache(chk_map, what)
      :return, chk_map when chk_map? -> {:halt, chk_map}
      :return, %{found: found} -> {:halt, found}
    end)
  end

  @path_check_steps [:path, :stat]
  @doc false
  def path_find(chk_map, {_mod, key}) do
    opts = Map.get(chk_map, :config)
    paths = get_in(opts, [key, @search]) || ["."]
    dir = to_string(key)

    Enum.reduce(paths, chk_map, fn
      # NOTE: path found, spin through remaining paths
      _search_path, %{found: <<_::binary>>} = chk_map ->
        chk_map

      search_path, chk_map ->
        Enum.reduce(@path_check_steps, chk_map, fn
          :path = key, chk_map -> path_make(search_path, dir, key, chk_map)
          :stat, chk_map -> path_stat(:stat, :found, chk_map)
        end)
    end)
    |> cmap_cont()
  end

  # NOTE: must store path because File.stat/2 does not return path
  @doc false
  def path_make(search, dir, key, chk_map) do
    parts = [search, dir]

    case search do
      # NOTE: absolute path, use as-is
      <<"/"::binary, _::binary>> -> parts
      # NOTE: relative path, prepend cwd
      _ -> [File.cwd!() | parts]
    end
    |> Path.join()
    # NOTE: cmap_put uses key and chk_map from function context
    |> cmap_put(:no_tuple)
  end

  @path_type :directory
  @doc false
  def path_stat(:stat, store_key, %{path: path} = chk_map) do
    # NOTE: ensure the destination keys don't exist because we merge with chk_map
    chk_map = Map.drop(chk_map, [:stat, store_key])
    stat = File.stat(path, @stat_opts)

    case stat do
      {:ok, %{type: @path_type, access: x}} when x in @access_want -> %{store_key => path}
      _x -> %{store_key => :none}
    end
    |> Map.put(:stat, stat)
    |> cmap_merge(:no_tuple)
  end
end
