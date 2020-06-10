defmodule ExtraMod do
  use GenServer

  ##
  ## Public API
  ##

  @doc """
      Compile files located in hot-stage


        ### Examples
        iex> Helen.Application.hot_load("hot-stage", :rm)

        Options:
          directory to load (default: "hot-stage")
          :rm  = delete files after loading (default)
          :no_rm = keep files after loading

  """
  @doc since: "0.0.15"
  def hot_load(dir, opts \\ [rm: true, base: "extra-mods"])
      when is_binary(dir) and is_list(opts) do
    GenServer.call(__MODULE__, {:hot_load, dir, opts})
  end

  @doc """
  Get the current state (diagnositic support)
  """
  @doc since: "0.0.23"
  def state, do: :sys.get_state(__MODULE__)

  ##
  ## GenServer Implementation
  ##

  def start_link(args) when is_list(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    default_opts = %{load_opts: [base: "extra-mods", dirs: ["always", "hot"]]}

    opts_map = Map.merge(default_opts, Enum.into(opts, %{}))
    state = %{loaded_modules: [], opts: opts_map}

    {:ok, state, {:continue, :load_extra_modules}}
  end

  @impl true
  def handle_call(
        {:hot_load, dir, opts},
        _from,
        %{loaded_modules: loaded, opts: %{load_opts: opts}} = s
      ) do
    # ensure that :base always exists
    opts = Keyword.put_new(opts, :base, "extra-mods")

    mods = mod_load(dir, opts)
    loaded = loaded ++ [mods]
    {:reply, mods, Map.put(s, :loaded_modules, loaded)}
  end

  @impl true
  def handle_call(msg, _from, %{} = s) do
    {:reply, {:no_match, msg}, s}
  end

  @impl true
  def handle_cast(_msg, %{} = s) do
    {:noreply, s}
  end

  @impl true
  def handle_continue(:load_extra_modules, %{opts: %{load_opts: load_opts}} = s) do
    with :ok <- ensure_directories(load_opts),
         mods <- mod_load("always", load_opts) do
      {:noreply, Map.put(s, :loaded_modules, mods)}
    else
      error ->
        {:noreply, Map.put(s, :loaded_modules, {:error, error})}
    end
  end

  def mod_load(dir, opts) do
    import File, only: [cwd: 0, ls: 1, rm: 1]
    import Path, only: [join: 1]

    with :ok <- Code.put_compiler_option(:ignore_module_conflict, true),
         # hot loading of modules is always relative to the cwd
         {:ok, curr_dir} <- cwd(),
         # get the base directory from the opts
         base <- Keyword.get(opts, :base, "extra-mods"),
         # confirm it's actually set and a binary
         {:base, base, true} <- {:base, base, is_binary(base)},
         # assemble the directory for the modules to load
         mod_dir <- [curr_dir, base, dir] |> join(),
         # ls the files
         {:ok, files} <- ls(mod_dir) do
      # compile the files in the module directory
      for f <- files do
        # actual file to compile
        f_actual = [mod_dir, f] |> join()

        # compile the file and assuming only a single module per file
        # for tracking purposes
        {mod, _bytecode} = Code.compile_file(f_actual) |> hd()

        # delete the files, if requested
        if Keyword.get(opts, :rm, false), do: _rc = rm(f_actual)

        Code.put_compiler_option(:ignore_module_conflict, false)
        mod
      end
    else
      error ->
        Code.put_compiler_option(:ignore_module_conflict, false)
        error
    end
  end

  ##
  ## Private
  ##

  defp ensure_directories(opts) do
    opts_map = Enum.into(opts, %{})

    with %{base: b, dirs: dirs} when is_binary(b) and is_list(dirs) <- opts_map,
         {:ok, curr_dir} <- File.cwd(),
         # what directories need to be created?
         needs <-
           (for d <- dirs do
              p = [curr_dir, b, d] |> Path.join()
              {p, File.dir?(p)}
            end),

         # create each needed directory
         res <-
           (for {p, false} <- needs do
              File.mkdir_p(p)
            end),

         # if so, were all directories created successfully?
         {:failures, true, _res} <-
           {:failures, Enum.all?(res, fn x -> x == :ok end), res} do
      :ok
    else
      # directories already existed
      {:failures, false, []} -> :ok
      # attempted to create directiories but experienced trouble
      {:failures, false, res} -> {:ensure_dirs, {:failed, res}}
      error -> {:ensure_dirs, error}
    end
  end
end
