defmodule ExtraMod do
  use GenServer
  use Timex

  ##
  ## Public API
  ##

  @doc """
      Compile files located in hot-stage


        ### Examples
        iex> Helen.Application.hot_load("hot-stage", :rm)

        Options:
          directory to load (default: "hot")
          rm: true   -> remove files after loading
          rm: false  -> keep files after loading (default)
  """
  @doc since: "0.0.15"
  def hot_load(dir \\ "hot", opts \\ [rm: false])
      when is_binary(dir) and is_list(opts) do
    GenServer.call(__MODULE__, {:hot_load, dir, opts})
  end

  def sleep(ms, opts_or_state \\ [])

  def sleep(ms, opts) when is_list(opts) do
    sleep(ms, %{opts: opts})
  end

  def sleep(ms, state) when is_map(state) do
    import Timex.Duration, only: [elapsed: 2, now: 0, to_milliseconds: 1]

    state = Map.put_new(state, :remaining_ms, ms)
    start = Duration.now()

    handler = state[:opts][:handler]

    if ms > 0 do
      receive do
        :abort -> handler.(:abort)
        msg -> msg
      after
        trunc(ms) -> nil
      end

      elapsed_ms = elapsed(now(), start) |> to_milliseconds()

      state =
        Map.update(state, :remaining_ms, ms - elapsed_ms, fn
          x when x > 0 -> trunc(x - elapsed_ms)
          x -> trunc(x)
        end)

      state = Map.update(state, :loops, 1, &(&1 + 1))

      sleep(state[:remaining_ms], state)
    else
      state
    end
  end

  @doc """
  Get the current state (diagnositic support)
  """
  @doc since: "0.0.23"
  def state, do: :sys.get_state(__MODULE__)

  ##
  ## Task Start, Abort, Result Storage and Info
  ##

  @doc """
  Abort an existing task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_abort({mod, key}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    GenServer.call(__MODULE__, {:task_abort, mod, key, opts})
  end

  @doc """
  Get an existing task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_get_by({mod, key}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    GenServer.call(__MODULE__, {:task_get_by, mod, key, opts})
  end

  @doc """
  Put the state of a task identified by Module and Key

  This function allows the internal state of the the task to be retrieved by
  other interested tasks.
  """
  @doc since: "0.0.23"
  def task_put_state({mod, key, state}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    GenServer.call(
      __MODULE__,
      {:task_put_key_in_task, mod, key, :state, state, opts}
    )
  end

  @doc """
  Put the state of a task identified by Module and Key

  This function allows the internal state of the the task to be retrieved by
  other interested tasks.
  """
  @doc since: "0.0.23"
  def task_get_state({mod, key}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    GenServer.call(
      __MODULE__,
      {:task_get_key_in_task, mod, key, :state, opts}
    )
  end

  @doc """
  Start a new task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_start({mod, key, func, task_opts}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(task_opts) and
             is_list(opts) do
    GenServer.call(__MODULE__, {:task_start, mod, key, func, task_opts, opts})
  end

  @doc """
  Retrieve the latest status for a task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_status({mod, key}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    task_get_by({mod, key}, opts) |> Map.get(:status, "none")
  end

  @doc """
  Store the return code of a task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_store_rc({mod, key, rc}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    GenServer.call(__MODULE__, {:task_store_rc, mod, key, rc, opts})
  end

  @doc """
  Store the status of a task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_store_status({mod, key, status}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(opts) do
    GenServer.call(__MODULE__, {:task_store_status, mod, key, status, opts})
  end

  @doc """
  Store the status (represented as iodata) of a task identified by Module and Key
  """
  @doc since: "0.0.23"
  def task_store_msg(iodata, {mod, key}, opts \\ [])
      when is_atom(mod) and is_atom(key) and is_list(iodata) and is_list(opts) do
    status = IO.iodata_to_binary(iodata)
    GenServer.call(__MODULE__, {:task_store_status, mod, key, status, opts})
  end

  @doc """
  Get the current state (diagnositic support)
  """
  @doc since: "0.0.23"
  def tasks, do: state() |> Map.get(:tasks, [])

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
    state = %{loaded_modules: [], opts: opts_map, tasks: %{}}

    Process.flag(:trap_exit, true)

    {:ok, state, {:continue, :load_extra_modules}}
  end

  @impl true
  def handle_call(
        {:hot_load, dir, opts},
        _from,
        %{loaded_modules: loaded, opts: %{load_opts: load_opts}} = s
      ) do
    # ensure that :base always exists
    base = Keyword.get(load_opts, :base)
    opts = Keyword.put_new(opts, :base, base)

    mods = mod_load(dir, opts)
    loaded = loaded ++ [mods]
    {:reply, mods, Map.put(s, :loaded_modules, loaded)}
  end

  #
  ## task handle_call/3
  #

  @doc false
  @impl true
  def handle_call({:task_abort, mod, key, _opts}, _from, s) do
    with %{pid: p, ref: r} = t when is_pid(p) <- task_by(mod, key, s),
         # if the process is alive then exit it with :extramod_abort
         {:alive?, true} <- {:alive?, Process.alive?(p)},
         _anything <- Process.exit(p, :extramod_abort),
         # flag that the task has been aborted
         # NOTE: remainder of task map updates done upon receipt of :EXIT msg
         task <- Map.put(t, :abort, true),
         # update the tasks map
         %{tasks: tasks} <- s,
         tasks <- Map.put(tasks, r, task),
         # update the state
         state <- Map.put(s, :tasks, tasks) do
      {:reply, task, state}
    else
      %{pid: nil} -> {:reply, {:not_found, {mod, key}}, s}
      {:alive?, false} -> {:reply, {:not_running, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  @doc false
  @impl true
  def handle_call({:task_get_by, mod, key, _opts}, _from, s) do
    with %{mod: m} = t when is_atom(m) <- task_by(mod, key, s) do
      {:reply, t, s}
    else
      %{mod: nil} -> {:reply, {:not_found, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  @doc false
  @impl true
  def handle_call({:task_get_key_in_task, mod, key, task_key, _opts}, _from, s) do
    with %{mod: m, task_keys: tk} when is_atom(m) <- task_by(mod, key, s) do
      val = Map.get(tk, task_key, %{})
      {:reply, val, s}
    else
      %{mod: nil} -> {:reply, {:not_found, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  @doc false
  @impl true
  def handle_call(
        {:task_put_key_in_task, mod, key, task_key, val, _opts},
        _from,
        s
      ) do
    with %{pid: p, ref: r, task_keys: tk} = t when is_pid(p) <-
           task_by(mod, key, s),
         # stuff the value into task_keys using the specified task_key
         task_keys <- Map.put(tk, task_key, val),
         # update the task with the new task keys
         task <- Map.put(t, :task_keys, task_keys),
         # get the tasks map from the state and put the updated task
         %{tasks: tasks} <- s,
         tasks <- Map.put(tasks, r, task),
         # update the state
         state <- Map.put(s, :tasks, tasks) do
      {:reply, {:ok}, state}
    else
      %{pid: nil, ref: _r} -> {:reply, {:not_found, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  @doc false
  @impl true
  def handle_call({:task_start, mod, key, func, task_opts, _opts}, _from, s) do
    # create the base task map.  we'll add pid and ref to it once the
    # task is started.
    base_map = %{mod: mod, key: key, func: func, task_opts: task_opts}

    with %{pid: nil, ref: existing_ref} <- task_by(mod, key, s),
         # we either just found an existing task that was previously run or
         # or a task for mod, key we've never seen so spawn a new one
         pid <- Process.spawn(mod, func, [task_opts], [:link]),
         # establish a reference for this task mod, key
         new_ref <- make_ref(),
         # build the task map
         base_map <- Map.merge(task_default_map(), base_map),
         task_map <- Map.merge(base_map, %{pid: pid, ref: new_ref}),
         # store the task map in the tasks map
         %{tasks: tasks} <- s,
         tasks <- Map.put(tasks, new_ref, task_map),
         # if there was an existing task map then remove it
         tasks <- Map.drop(tasks, [existing_ref]),
         # update the state
         state <- %{s | tasks: tasks} do
      {:reply, {:ok, task_map}, state}
    else
      %{pid: _} -> {:reply, {:running, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  @doc false
  @impl true
  def handle_call({:task_store_rc, mod, key, rc, _opts}, _from, s) do
    with %{pid: p, ref: r} = t when is_pid(p) <- task_by(mod, key, s),
         # stuff the task rc into the task map
         task <- Map.put(t, :rc, rc),
         # update the tasks map
         %{tasks: tasks} <- s,
         tasks <- Map.put(tasks, r, task),
         # update the state
         state <- Map.put(s, :tasks, tasks) do
      {:reply, {:ok}, state}
    else
      %{pid: nil, ref: _r} -> {:reply, {:not_found, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  @doc false
  @impl true
  def handle_call({:task_store_status, mod, key, status, _opts}, _from, s) do
    with %{pid: p, ref: r} = t when is_pid(p) <- task_by(mod, key, s),
         # stuff the task rc into the task map
         task <- Map.put(t, :status, status),
         # update the tasks map
         %{tasks: tasks} <- s,
         tasks <- Map.put(tasks, r, task),
         # update the state
         state <- Map.put(s, :tasks, tasks) do
      {:reply, {:ok}, state}
    else
      %{pid: nil, ref: _r} -> {:reply, {:not_found, {mod, key}}, s}
      error -> {:reply, {:error, error}, s}
    end
  end

  ##
  ## handle_call/3 catch all
  ##

  @impl true
  def handle_call(msg, _from, %{} = s) do
    {:reply, {:extra_mod_handle_call_no_match, {:msg, msg}, {:state, s}}, s}
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

  @doc false
  @impl true
  def handle_info({:EXIT, pid, :normal}, s) do
    with %{ref: r} = t when is_reference(r) <- task_by(pid, s),
         # this is a known pid, update the task info
         task <- Map.merge(t, %{pid: nil, exit: true}),
         %{tasks: tasks} <- s,
         # update the task map
         tasks <- Map.put(tasks, r, task),
         # update the state
         state <- Map.put(s, :tasks, tasks) do
      {:noreply, state}
    else
      _unknown_pid ->
        {:noreply, Map.put(s, :last_unknown_pid_exit, {pid, :normal})}
    end
  end

  @doc false
  @impl true
  def handle_info({:EXIT, pid, :extramod_abort}, s) do
    with %{pid: p, ref: r} = t when p == pid <- task_by(pid, s),
         # this is a known pid, update the task info
         task <- Map.merge(t, %{pid: nil, abort: true}),
         %{tasks: tasks} <- s,
         # update the task map
         tasks <- Map.put(tasks, r, task),
         # update the state
         state <- Map.put(s, :tasks, tasks) do
      {:noreply, state}
    else
      _unknown_pid -> {:noreply, s}
    end
  end

  @doc false
  @impl true
  def handle_info({:EXIT, pid, reason}, s) do
    {:noreply, Map.put(s, :last_unknown_pid_exit, {pid, reason})}
  end

  ##
  ## Private
  ##

  #
  ## Hot Loading Support Functions
  #

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

  defp mod_load(dir, opts) do
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
         {:ok, files} <- ls(mod_dir),
         files <- Enum.sort(files) do
      # compile the files in the module directory
      for f <- files do
        # actual file to compile
        f_actual = [mod_dir, f] |> join()

        # compile the file and assuming only a single module per file
        # for tracking purposes
        {mod, _bytecode} = Code.compile_file(f_actual) |> hd()

        if function_exported?(mod, :init, 1), do: apply(mod, :init, [])

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

  #
  # Task Lookup Helpers
  #

  defp task_by(mod, key, %{tasks: tasks}) when is_atom(mod) and is_atom(key) do
    match = fn
      {_ref, %{mod: m, key: k}} when m == mod and k == key -> true
      {_ref, _task} -> false
    end

    with {_ref, %{mod: m} = t} when is_atom(m) <- Enum.find(tasks, match) do
      t
    else
      # NOTE:
      #   if the task is not found return the default task map containing
      #   mod: nil so the calling function can pattern match
      _not_found -> task_default_map()
    end
  end

  defp task_by(pid, %{tasks: tasks}) when is_pid(pid) do
    match = fn
      {_ref, %{pid: p}} when p == pid -> true
      {_ref, _task} -> false
    end

    with {_ref, %{pid: p} = t} when is_pid(p) <- Enum.find(tasks, match) do
      t
    else
      # NOTE:
      #   if the task is not found return the default task map containing
      #   pid: nil so the calling function can pattern match
      _not_found -> task_default_map()
    end
  end

  defp task_default_map,
    do: %{
      pid: nil,
      ref: nil,
      mod: nil,
      func: nil,
      task_opts: nil,
      task_keys: %{}
    }
end
