defmodule Broom do
  use GenServer

  # @callback init(init_arg :: term) ::
  #             {:ok, state}
  #             | {:ok, state, timeout | :hibernate | {:continue, term}}
  #             | :ignore
  #             | {:stop, reason :: any}
  #           when state: any
  #
  # @callback handle_call(request :: term, from, state :: term) ::
  #             {:reply, reply, new_state}
  #             | {:reply, reply, new_state,
  #                timeout | :hibernate | {:continue, term}}
  #             | {:noreply, new_state}
  #             | {:noreply, new_state, timeout | :hibernate | {:continue, term}}
  #             | {:stop, reason, reply, new_state}
  #             | {:stop, reason, new_state}
  #           when reply: term, new_state: term, reason: term

  @callback broom :: term
  @callback child_spec(term) :: term
  @callback cmd_counts :: Keyword.t()
  @callback cmd_counts_reset(Keyword.t()) :: :ok
  @callback cmds_tracked :: [cmd]
  @callback default_opts :: Keyword.t()
  @callback find_refid(term) :: {:ok, term} | {term, term}
  @callback insert_and_track(Ecto.Changeset.t()) :: track_result

  @callback orphan(cmd) ::
              {:orphan, {:ok, Ecto.Schema.t()}}
              | {:acked, {:ok, Ecto.Schema.t()}}

  @callback orphan_list(term) :: [term]
  @callback reload(cmd) :: Ecto.Schema.t({} | nil)
  @callback start_link(list) :: term
  @callback update(cmd, opts) :: {:ok, cmd} | {term, term}

  @optional_callbacks []

  # @optional_callbacks reload: 1,
  #                     terminate: 2,
  #                     handle_info: 2,
  #                     handle_cast: 2,
  #                     handle_call: 3,
  #                     format_status: 2,
  #                     handle_continue: 2

  @typedoc "Argument to orphan/1, reload/1"
  @type cmd :: Ecto.Schema.t()

  @typedoc "Argument to track/1"
  @type msg :: %{cmd: {term, cmd}}
  @type track_result :: %{cmd: {:ok | term, cmd}, broom_track: :ok | term}
  @type opts :: term

  # @typedoc "Return values of `start*` functions"
  # @type on_start ::
  #         {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}
  #
  # @typedoc "The GenServer name"
  # @type name :: atom | {:global, term} | {:via, module, term}
  #
  # @typedoc "Options used by the `start*` functions"
  # @type options :: [option]
  #
  # @typedoc "Option values used by the `start*` functions"
  # @type option ::
  #         {:debug, debug}
  #         | {:name, name}
  #         | {:timeout, timeout}
  #         | {:spawn_opt, Process.spawn_opt()}
  #         | {:hibernate_after, timeout}
  #
  # @typedoc "Debug options supported by the `start*` functions"
  # @type debug :: [:trace | :log | :statistics | {:log_to_file, Path.t()}]
  #
  # @type server :: pid | name | {atom, node}
  #
  # @type from :: {pid, tag :: term}

  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour Broom

      def broom do
        parts = [[Module.split(__MODULE__) |> hd()], "Broom"] |> List.flatten()
        Module.concat(parts)
      end

      defoverridable broom: 0

      def child_spec(args) do
        %{start: {_, :start_link, x}} = spec = Broom.child_spec(args)

        %{spec | start: {__MODULE__, :start_link, x}}
      end

      defoverridable child_spec: 1

      def cmd_counts_reset(opts \\ [:orphaned, :errors]) when is_list(opts) do
        Broom.counts_reset(broom(), opts)
      end

      defoverridable cmd_counts_reset: 1

      def cmd_counts, do: Broom.tracked_counts(broom())
      defoverridable cmd_counts: 0

      def cmds_tracked, do: Broom.tracked_cmds(broom())
      defoverridable cmds_tracked: 0

      def default_opts, do: []
      defoverridable default_opts: 0

      def find_refid(ref) when is_binary(ref),
        do: Repo.get_by(__MODULE__, refid: ref) |> Repo.preload([:device])

      defoverridable find_refid: 1

      @doc """
        Default implementation of insert_and_track/1 that calls
        Broom.insert_and_track(broom(), cs)

        ## Override notes:
          1. Typical reason to override is when some action (e.g. altering
             the changeset) prior to insert and track.
          2. When overriden, be certain to call Broom.insert_and_track/2
             the expected map
      """
      def insert_and_track(cs), do: Broom.insert_and_track(broom(), cs)
      defoverridable insert_and_track: 1

      def orphan(%{acked: false} = cmd) do
        import TimeSupport, only: [utc_now: 0]

        cmd = reload(cmd)
        {:orphan, update(cmd, acked: true, ack_at: utc_now(), orphan: true)}
      end

      defoverridable orphan: 1

      def orphan_list(opts \\ []) when is_list(opts) do
        import Ecto.Query, only: [from: 2]
        import TimeSupport, only: [utc_shift_past: 1]

        # sent before passed as an option will override the app env config
        # if not passed in then grab it from the config
        # finally, as a last resort use the hardcoded value
        sent_before_opts = Keyword.take(opts, [:sent_before, seconds: 31])
        preloads = __MODULE__.__schema__(:associations)

        before = utc_shift_past(sent_before_opts)

        from(x in __MODULE__,
          where:
            x.acked == false and x.orphan == false and x.inserted_at <= ^before
        )
        |> Repo.all()
        |> Repo.preload(preloads)
      end

      defoverridable orphan_list: 1

      def reload(%{id: id}) do
        Repo.get_by(__MODULE__, id)
      end

      defoverridable reload: 1

      def start_link(opts) do
        base_opts =
          Application.get_application(__MODULE__)
          |> Application.get_env(__MODULE__, default_opts())

        # override any opts from config or local default
        opts =
          Keyword.merge(base_opts, opts)
          |> Keyword.merge(module: __MODULE__, name: broom())

        Broom.start_link(opts)
      end

      defoverridable start_link: 1

      @before_compile Broom
    end
  end

  defmacro __before_compile__(%{aliases: _aliases} = _env), do: nil

  ##
  ## GenServer Start and Init
  ##

  def init(args) do
    state = %{
      opts: args,
      tasks: [],
      tracker: %{},
      timers: [],
      counts: [],
      opts_vsn: 0
    }

    {:ok, state |> schedule_metrics()}
  end

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(Broom, opts, name: name)
  end

  ##
  ## Broom Public API
  ##

  def acked?(%{} = c) when is_struct(c) do
    %{acked: ack} = cmd = reload(c)

    # return a tuple that can be pattern matched
    {:acked, ack, cmd}
  end

  def insert_and_track(server, %Ecto.Changeset{} = cs) do
    with {:cs_valid, true} <- {:cs_valid, cs.valid?},
         {:ok, _cmd} = cmd_rc <- Repo.insert(cs, returning: true),
         # TODO
         #   as of 0.0.23 we simulate the ultimate implementaton of
         #   the passing of a msg map
         msg <- %{cmd: cmd_rc},
         %{cmd: {:ok, _cmd}} = msg <- track(server, msg) do
      msg
    else
      error -> {:error, error}
    end
  end

  def release(server, %{cmd: {:ok, cmd}} = msg)
      when is_struct(cmd) do
    rc = GenServer.cast(server, {:release, msg})
    Map.put(msg, :broom_untrack, rc)
  end

  @doc """
    Reload an %Ecto.Schemea.t that is a command.

    Automatically preloads the association :device, if part of schema

    Raises if not found, otherwise returns the reloaded
  """
  @doc since: "0.0.24"
  def reload(%{__struct__: schema, id: id} = cmd) when is_struct(cmd) do
    preloads = Map.take(cmd, [:device]) |> Map.keys()

    Repo.get_by!(schema, id: id) |> Repo.preload(preloads)
  end

  @doc """
  Reset the orphan count
  """
  @doc since: "0.0.24"
  def counts_reset(server, opts \\ [:orphaned, :errors]) when is_list(opts) do
    GenServer.call(server, {:count_reset, opts})
  end

  def track(server, %{cmd: {:ok, cmd}} = msg) when is_struct(cmd) do
    rc = GenServer.cast(server, {:track, msg})

    # return the msg passed, track is intended for use in a pipeline
    Map.put(msg, :broom_track, rc)
  end

  def tracked_cmds(server) do
    for {_k, v} <- :sys.get_state(server) |> Map.get(:tracker), do: v
  end

  def tracked_counts(server) do
    :sys.get_state(server) |> Map.get(:counts)
  end

  ##
  ## GenServer handle_* implementation
  ##

  @doc false
  def handle_call({:count_reset, opts}, _from, %{counts: counts} = s) do
    new_counts =
      for(x <- opts, do: Keyword.new() |> Keyword.put(x, 0)) |> List.flatten()

    counts = Keyword.merge(counts, new_counts)

    {:reply, :ok, %{s | counts: counts}}
  end

  @doc false
  def handle_cast({:release, %{cmd: _cmd_rc}}, %{tracker: _track} = s) do
    {:noreply, s}
  end

  @doc false
  def handle_cast({:track, %{cmd: {_rc, cmd}}}, %{opts: opts} = s) do
    import TimeSupport, only: [duration: 1, duration_ms: 1]

    timeout = opts[:orphan][:sent_before] |> duration()
    ms = duration_ms(timeout)

    %{refid: refid, __struct__: schema} = cmd
    timer = Process.send_after(self(), {:possible_orphan, refid}, ms)

    track_map = %{refid: refid, cmd: cmd, schema: schema, timer: timer}
    tracker = Map.put(s[:tracker], refid, track_map)

    s = increment_count(s, :tracked)

    {:noreply, Map.merge(s, %{tracker: tracker})}
  end

  @doc false
  def handle_info({:possible_orphan, ref}, %{} = s) do
    # the timeout msg for a command has arrived and we must determine if:
    #
    #  1. the cmd has already been acked (happy path)
    #  2. the cmd has not been acked and is a likely an orphan
    #     a. double check the db to ensure it hasn't been acked
    #     b. if the db indicate it's not acked then it's an orphan
    #
    with %{refid: _} = tm <- s[:tracker][ref],
         # double check nothing crossed in the night
         {:acked, false, cmd} <- acked?(tm[:cmd]),
         # it's an orphan, update the counts and remove it from the tracker
         s <- increment_count(s, :orphaned) |> remove_from_tracker(ref),
         {:orphan, {:ok, _cmd}} <- orphan(cmd) do
      {:noreply, s}
    else
      # the refid wasn't in the tracker, not an orphan
      nil -> {:noreply, s}
      # glad we double checked, not an orphan after all
      {:acked, true, _cmd} -> {:noreply, remove_from_tracker(s, ref)}
      # some other error has occurred, store it in the state
      error -> {:noreply, store_update_error(s, ref, error)}
    end
  end

  @doc false
  def handle_info({:report_metrics, opts_vsn}, %{} = s) do
    with true <- opts_vsn == s[:opts_vsn] do
      {:noreply, report_metrics(s) |> schedule_metrics()}
    else
      # the opts have changed (message opts_vsn != state opts_vsn) so skip
      # this report and simply schedule the next (using the new opts)
      false -> {:noreply, schedule_metrics(s)}
    end
  end

  defp increment_count(%{counts: c} = s, key) when is_atom(key) do
    counts = Keyword.update(c, key, 1, &(&1 + 1))
    Map.put(s, :counts, counts)
  end

  ##
  ## NOTE
  ## to ensure separation of concerns we only allow Broom to orphan a command
  ##
  defp orphan(%{__struct__: schema} = cmd) do
    import TimeSupport, only: [utc_now: 0]

    cmd = reload(cmd)

    {:orphan,
     apply(schema, :update, [
       cmd,
       [acked: true, ack_at: utc_now(), orphan: true]
     ])}
  end

  defp remove_from_tracker(%{tracker: t} = s, ref) do
    %{s | tracker: Map.drop(t, [ref])}
  end

  defp report_metrics(%{counts: counts, opts: opts} = state) do
    import Fact.Influx, only: [write: 2]
    import TimeSupport, only: [unix_now: 1]

    datapoint_map = %{
      points: [
        %{
          measurement: "switch",
          fields: Enum.into(counts, %{}),
          tags: %{mod: Atom.to_string(opts[:module])},
          timestamp: unix_now(:nanosecond)
        }
      ]
    }

    write_rc = write(datapoint_map, precision: :nanosecond)

    Map.put(state, :last_datapoint_write, write_rc)
  end

  defp schedule_metrics(%{opts_vsn: v, opts: opts} = state) do
    import TimeSupport, only: [duration: 1, duration_ms: 1]

    timeout = opts[:metrics] |> duration()
    ms = duration_ms(timeout)
    Process.send_after(self(), {:report_metrics, v}, ms)

    state
  end

  defp store_update_error(%{errors: e} = s, ref, error) do
    %{s | errors: Map.put(e, ref, error)} |> increment_count(:errors)
  end

  # def update(%{__struct__: schema} = cmd, opts) when is_list(opts) do
  #   set = Keyword.take(opts, possible_changes()) |> Enum.into(%{})
  #   cs = changeset(cmd, set)
  #
  #   if cs.valid?,
  #     do: {:ok, Repo.update!(cs, returning: true)},
  #     else: {:invalid_changes, cs}
  # end
end
