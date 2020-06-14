defmodule Janitor do
  @moduledoc false

  # require Logger
  # use GenServer
  # use Timex
  #
  # use Config.Helper
  # import Process, only: [send_after: 3]
  # import TimeSupport, only: [duration_ms: 1]
  #

  #     def purge(opts \\ []) when is_list(opts) do
  #       opts = Keyword.merge(config(:purge) |> Keyword.get(:opts, []), opts)
  #
  #       dryrun = Keyword.get(opts, :dryrun, false)
  #
  #       trash = purge_list(opts)
  #
  #       if dryrun do
  #         log?(:dryrun, true) &&
  #           Logger.info([
  #             "DRY RUN >> found ",
  #             inspect(Enum.count(trash)),
  #             " trash items for ",
  #             inspect(__MODULE__)
  #           ])
  #
  #         {:dryrun, [trash: trash]}
  #       else
  #         Janitor.empty_trash(trash, [mod: __MODULE__] ++ opts)
  #         {:purge_queued, [trash: trash]}
  #       end
  #     end
  #
  #     def purge_list(opts \\ []) when is_list(opts) do
  #       import Ecto.Query, only: [from: 2]
  #
  #       older = older_than(opts)
  #
  #       from(x in __MODULE__,
  #         where: x.inserted_at <= ^older
  #       )
  #       |> Repo.all()
  #     end
  #

  #
  #     #
  #     ## Private
  #     #
  #     def older_than(opts \\ [older_than: [months: 3]]) when is_list(opts) do
  #       import TimeSupport, only: [utc_shift_past: 1]
  #
  #       # :older_than passed as an option will override the app env config
  #       # if not passed in then grab it from the config
  #       # finally, as a last resort use the hardcoded value
  #       older_than_opts =
  #         Keyword.get(
  #           opts,
  #           :older_than,
  #           purge_config(:older_than, months: 3)
  #         )
  #
  #       utc_shift_past(older_than_opts)
  #     end
  #   end
  # end
  #

  #
  # #
  # # opts:
  # #  mod:  Module the trash belongs to
  #
  # def empty_trash(trash, opts \\ []) when is_list(trash) and is_list(opts) do
  #   GenServer.cast(__MODULE__, {:empty_trash, trash, opts})
  # end
  #

  # #
  # ## GenServer Start Up and Shutdown Callbacks
  # #

  # def terminate(reason, s) do
  #   log?(s, :init) &&
  #     Logger.info(["terminating with reason ", inspect(reason, pretty: true)])
  # end
  #
  # #
  # ## GenServer callbacks
  # #
  #
  # def handle_call(
  #       %{action: :reset_orphan_count, opts: _opts},
  #       _from,
  #       %{
  #         counts: counts
  #       } = s
  #     ) do
  #   counts = Keyword.put(counts, :orphan_count, 0)
  #
  #   {:reply, counts, %{s | counts: counts}}
  # end
  #
  # # update Janitor opts
  # def handle_call(
  #       %{action: :update_opts, opts: new_opts},
  #       _from,
  #       %{opts: opts} = s
  #     ) do
  #   keys_to_return = Keyword.keys(new_opts)
  #   new_opts = DeepMerge.deep_merge(opts, new_opts)
  #
  #   was_rc = Keyword.take(opts, keys_to_return)
  #   is_rc = Keyword.take(new_opts, keys_to_return)
  #
  #   {:reply, {:ok, [was: was_rc, is: is_rc]},
  #    %{s | opts: new_opts, opts_vsn: Ecto.UUID.generate()}}
  # end
  #
  # # update module which used Janitor
  # def handle_call(
  #       %{action: :update_opts, mod: update_mod, opts: new_opts},
  #       _from,
  #       %{mods: mods, opts: _opts} = s
  #     ) do
  #   keys_to_return = Keyword.keys(new_opts)
  #
  #   with %{track: _, opts: opts} = mod <- Map.get(mods, update_mod),
  #        new_opts <- DeepMerge.deep_merge(opts, new_opts),
  #        was_rc <- Keyword.take(opts, keys_to_return),
  #        is_rc <- Keyword.take(new_opts, keys_to_return),
  #        mods <- %{
  #          mods
  #          | mod => %{mod | opts: new_opts, opts_vsn: Ecto.UUID.generate()}
  #        } do
  #     {:reply, {:ok, [was: was_rc, is: is_rc]}, %{s | mods: mods}}
  #   else
  #     _anything ->
  #       {:reply, {:failed, %{mod: update_mod, mods: mods}}}
  #   end
  # end
  #
  #
  # def handle_cast({:empty_trash, trash, opts}, %{tasks: tasks} = s) do
  #   empty_trash = fn ->
  #     mod = Keyword.get(opts, :mod, nil)
  #
  #     {elapsed, results} =
  #       Duration.measure(fn ->
  #         for %{id: _} = x <- trash do
  #           Repo.delete(x)
  #         end
  #       end)
  #
  #     {:trash, mod, elapsed, results}
  #   end
  #
  #   task = Task.async(empty_trash)
  #
  #   tasks = [task] ++ tasks
  #
  #   {:noreply, %{s | tasks: tasks}}
  # end
  #

  #
  # def handle_continue(
  #       {:startup},
  #       %{opts: _opts, mods: _mods, starting_up: true} = s
  #     ) do
  #   check_mods = startup_orphan_check_modules()
  #
  #   {:noreply, schedule_metrics(s),
  #    {:continue, {:startup_orphan_check, check_mods}}}
  # end
  #
  # def handle_continue(
  #       {:startup_orphan_check, _empty_list = []},
  #       %{opts: _opts, mods: _mods, starting_up: true} = s
  #     ) do
  #   {:noreply, s, {:continue, {:startup_complete}}}
  # end
  #
  # def handle_continue(
  #       {:startup_orphan_check, [check_mod | rest]},
  #       %{opts: _opts, mods: _mods, starting_up: true} = s
  #     )
  #     when is_atom(check_mod) do
  #   #
  #   # invoke the module to generate a possible orphan list
  #   orphans =
  #     apply(check_mod, :orphan_list, [])
  #     |> log_startup_possible_orphans(check_mod, s)
  #
  #   apply(check_mod, :track_list, [orphans])
  #
  #   {:noreply, s, {:continue, {:startup_orphan_check, rest}}}
  # end
  #
  # def handle_continue({:startup_complete}, %{starting_up: true} = s) do
  #   log?(s, :init) && Logger.info(["startup complete"])
  #   {:noreply, %{s | starting_up: false}}
  # end
  #
  #

  #
  # # quietly handle processes that :EXIT normally
  # def handle_info({:EXIT, pid, :normal}, %{tasks: tasks} = s) do
  #   tasks =
  #     Enum.reject(tasks, fn
  #       %Task{pid: search_pid} -> search_pid == pid
  #       _x -> false
  #     end)
  #
  #   {:noreply, %{s | tasks: tasks}}
  # end
  #
  # def handle_info({:EXIT, _pid, reason} = msg, state) do
  #   Logger.info([
  #     ":EXIT msg: ",
  #     inspect(msg, pretty: true),
  #     " reason: ",
  #     inspect(reason, pretty: true)
  #   ])
  #
  #   {:noreply, state}
  # end
  #
  # def handle_info({:DOWN, _ref, :process, _pid, :normal}, s) do
  #   # normal exit of a process
  #   {:noreply, s}
  # end
  #
  # def handle_info(
  #       {:DOWN, ref, :process, pid, _reason} = msg,
  #       %{} = s
  #     )
  #     when is_reference(ref) and is_pid(pid) do
  #   Logger.debug([
  #     "handle_info({:DOWN, ...} msg: ",
  #     inspect(msg, pretty: true),
  #     " state: ",
  #     inspect(s, pretty: true)
  #   ])
  #
  #   {:noreply, s}
  # end
  #
  # def handle_info({_ref, {:trash, mod, _elapsed, trash} = msg}, %{} = s) do
  #   log_trash_count(s, {mod, trash})
  #
  #   # send the actual results to the mod passed to empty trash
  #   # NOTE: GenServer.cast/2 handles unknown mods, pids
  #   GenServer.cast(mod, msg)
  #
  #   {:noreply, s}
  # end
  #
  # def handle_info(catchall, s) do
  #   Logger.warn(["handle_info(catchall): ", inspect(catchall, pretty: true)])
  #   {:noreply, s}
  # end
  #
end
