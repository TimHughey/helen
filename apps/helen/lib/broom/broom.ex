defmodule Broom do
  @moduledoc """
  Tracks and handles device command timeouts
  """

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
  @callback insert_and_track(Ecto.Changeset.t(), Keyword.t()) :: track_result

  @callback orphan(cmd) ::
              {:orphan, {:ok, Ecto.Schema.t()}}
              | {:acked, {:ok, Ecto.Schema.t()}}

  @callback orphan_list(term) :: [term]
  @callback reload(cmd) :: Ecto.Schema.t()
  @callback release(msg) :: msg
  @callback report_metrics(Keyword.t()) :: :ok
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

      def broom, do: Broom.make_module_name(__MODULE__)

      def child_spec(args) do
        %{start: {_, :start_link, x}} = spec = Broom.child_spec(args)

        %{spec | start: {__MODULE__, :start_link, x}}
      end

      def cmd_counts_reset(opts \\ [:orphaned, :errors]) when is_list(opts) do
        Broom.counts_reset(broom(), opts)
      end

      def cmd_counts, do: Broom.tracked_counts(broom())

      def cmds_tracked, do: Broom.tracked_cmds(broom())

      def default_opts, do: []

      def find_refid(ref) when is_binary(ref) do
        preloads = __MODULE__.__schema__(:associations)
        Repo.get_by(__MODULE__, refid: ref) |> Repo.preload(preloads)
      end

      @doc """
        Default implementation of insert_and_track/1 that calls
        Broom.insert_and_track(cs, opts, broom())

        ## Override notes:
          1. Typical reason to override is when some action (e.g. altering
             the changeset) prior to insert and track.
          2. When overriden, be certain to call Broom.insert_and_track/2
             with the altered changeset
      """
      def insert_and_track(cs, opts), do: Broom.insert_and_track(cs, opts, broom())

      def orphan(%{acked: false} = cmd) do
        import Helen.Time.Helper, only: [utc_now: 0]

        cmd = reload(cmd)
        {:orphan, update(cmd, acked: true, ack_at: utc_now(), orphan: true)}
      end

      def orphan_list(opts \\ []) when is_list(opts) do
        import Ecto.Query, only: [from: 2]
        import Helen.Time.Helper, only: [utc_shift_past: 1]

        # sent before passed as an option will override the app env config
        # if not passed in then grab it from the config
        # finally, as a last resort use the hardcoded value
        sent_before_opts = Keyword.take(opts, [:sent_before, "PT3.1S"])
        preloads = __MODULE__.__schema__(:associations)

        before = utc_shift_past(sent_before_opts)

        from(x in __MODULE__,
          where: x.acked == false and x.orphan == false and x.inserted_at <= ^before
        )
        |> Repo.all()
        |> Repo.preload(preloads)
      end

      def release(msg), do: Broom.release(broom(), msg)

      @doc """
        Reload a device command.

        Automatically preloads the associations [:alias, :device], if part of schema

        Raises if not found, otherwise returns the reloaded command
      """
      @doc since: "0.0.24"
      def reload(%{id: id} = cmd) when is_struct(cmd) do
        Repo.get_by!(__MODULE__, id: id)
        |> Repo.preload(__MODULE__.__schema__(:associations))
      end

      def start_link(_opts), do: default_opts() |> Broom.make_opts(__MODULE__) |> Broom.start_link()

      def report_metrics(opts \\ []), do: Broom.report_metrics_now(broom(), opts)

      defoverridable Broom
    end
  end

  ##
  ## GenServer Start and Init
  ##

  @impl true
  def init(args) do
    counts = [orphaned: 0, tracked: 0, released: 0, errors: 0]

    %{opts: args, tracker: %{}, counts: counts, metrics_timer: :never, metrics_rc: :never}
    |> schedule_metrics()
    |> reply_ok()
  end

  def start_link(opts), do: GenServer.start_link(Broom, opts, name: opts[:name])

  ##
  ## Broom Public API
  ##

  def acked?(%{__struct__: schema} = c) when is_struct(c) do
    %{acked: ack} = cmd = apply(schema, :reload, [c])

    # return a tuple that can be pattern matched
    {:acked, ack, cmd}
  end

  def insert_and_track(cs, opts, server) do
    cs
    |> insert(opts)
    |> track(server, opts)
    |> add_cmd_immediate_to_track_result_if_needed()
  end

  def insert(%Ecto.Changeset{valid?: true} = cs, _opts) do
    Repo.insert(cs, returning: true)
  end

  @doc """
  Reset the orphan count
  """
  @doc since: "0.0.24"
  def counts_reset(server, opts \\ [:orphaned, :errors]) when is_list(opts) do
    GenServer.call(server, {:count_reset, opts})
  end

  def make_module_name(mod) do
    ([Module.split(mod) |> hd()] ++ ["Broom"]) |> Module.concat()
  end

  def make_opts(default_opts, mod) do
    base_opts = [module: mod, name: make_module_name(mod)]

    case Application.get_env(:helen, mod, []) do
      [] -> base_opts ++ default_opts
      x when is_list(x) -> base_opts ++ x
    end
  end

  # NOTE!
  # as of 2021-05-05 this function contains backward compatible code
  # matching on cmd_rc is the intended final implementation
  def release(server, msg) do
    put_broom_rc = fn x -> put_in(msg, [:broom_rc], x) end

    case msg do
      %{cmd_rc: {:ok, cmd}} when is_struct(cmd) ->
        GenServer.cast(server, {:release, cmd.refid})
        put_broom_rc.({:requested, cmd.refid})

      %{cmd_rc: {:ok, text}} when is_binary(text) ->
        put_broom_rc.({:ok, text})

      %{cmd: {:ok, cmd}} when is_struct(cmd) ->
        GenServer.cast(server, {:release, cmd.refid})
        put_broom_rc.({:requested_release, cmd.refid})

      _ ->
        put_broom_rc.({:ok, "unmatched release, will handle via orphan timer"})
    end
  end

  def report_metrics_now(server, opts) do
    GenServer.call(server, {:report_metrics, opts})
  end

  # (1 of 2) the insert was a success
  def track({:ok, schema} = cmd_rc, server, opts) do
    # create a map to populate as the server msg and as the return value
    msg = %{cmd_rc: cmd_rc, broom_rc: nil, server: server, opts: opts}

    # when the requestor is willing to wait for the ack we call the server, otherwise we cast
    # a tuple is returned (for consistency) regardless of call or cast
    call_track = fn
      true -> GenServer.call(server, {:track, msg})
      false -> {GenServer.cast(server, {:track, msg}), [track_requested: schema.refid]}
    end

    notify = opts[:notify_when_released] || false
    %{msg | broom_rc: notify |> call_track.()}
  end

  # (2 of 2) insert failed
  def track(rc, server, opts) do
    %{cmd_rc: rc, broom_rc: {:failed, "insert failed, unable to track"}, server: server, opts: opts}
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

  @impl true
  def handle_call({:count_reset, opts}, _from, %{counts: counts} = s) do
    new_counts = for(x <- opts, do: Keyword.new() |> Keyword.put(x, 0)) |> List.flatten()

    counts = Keyword.merge(counts, new_counts)

    {:reply, :ok, %{s | counts: counts}}
  end

  @impl true
  def handle_call({:track, %{cmd_rc: {_, schema}}}, {pid, _ref}, s) do
    handle_track(schema, pid, s) |> reply({:will_notify, schema.refid})
  end

  @impl true
  def handle_call({:report_metrics, opts}, _from, s) do
    # if opts contains a new report metrics option then put it in the state
    interval = opts[:interval] || s.opts[:metrics]

    %{s | opts: Keyword.replace(s.opts, :metrics, interval)}
    |> report_metrics()
    |> schedule_metrics
    |> reply({:ok, interval})
  end

  @impl true
  # NOTE!  new as of 2021-05-05
  # release an acked cmd matching on the cmd_rc (cmd update) result
  def handle_cast({:release, refid}, s) when is_binary(refid) do
    s
    |> remove_from_tracker(refid, :acked)
    |> increment_count(:released)
    |> noreply()
  end

  @impl true
  def handle_cast({:track, %{cmd_rc: {_, schema}}}, s) do
    handle_track(schema, nil, s) |> noreply()
  end

  @impl true
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
         s <- increment_count(s, :orphaned) |> remove_from_tracker(ref, :orphaned),
         {:orphan, {:ok, _cmd}} <- orphan(cmd) do
      {:noreply, s}
    else
      # the refid wasn't in the tracker, not an orphan
      nil -> {:noreply, s}
      # glad we double checked, not an orphan after all
      {:acked, true, _cmd} -> {:noreply, remove_from_tracker(s, ref, :acked)}
      # some other error has occurred, store it in the state
      error -> {:noreply, store_update_error(s, ref, error)}
    end
  end

  @impl true
  def handle_info(:report_metrics, s) do
    %{s | metrics_timer: nil} |> report_metrics() |> schedule_metrics() |> noreply()
  end

  ##
  ##
  ## Private
  ##
  ##

  # when the inserted command is already acked then add cmd as a signal for upstream
  defp add_cmd_immediate_to_track_result_if_needed(%{cmd_rc: rc} = res) do
    case rc do
      {:ok, %{acked: true, cmd: cmd}} -> put_in(res, [:cmd_acked], cmd)
      _ -> res
    end
  end

  defp handle_track(inserted_cmd, reply_to, %{opts: opts} = s) do
    import Helen.Time.Helper, only: [to_ms: 2]

    ms = opts[:orphan][:sent_before] |> to_ms("PT15S")

    %{refid: refid, __struct__: schema} = inserted_cmd
    timer = Process.send_after(self(), {:possible_orphan, refid}, ms)

    track_map = %{refid: refid, cmd: inserted_cmd, schema: schema, timer: timer, reply_to: reply_to}
    tracker = Map.put(s[:tracker], refid, track_map)

    increment_count(s, :tracked) |> put_in([:tracker], tracker)
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
    import Helen.Time.Helper, only: [utc_now: 0]

    cmd = apply(schema, :reload, [cmd])

    {:orphan, apply(schema, :update, [cmd, [acked: true, ack_at: utc_now(), orphan: true]])}
  end

  defp remove_from_tracker(%{tracker: t, opts: opts} = s, ref, disposition) do
    case t[ref] do
      %{reply_to: pid} when is_pid(pid) -> send(pid, {{opts[:name], :ref_released}, ref, disposition})
      _ -> nil
    end

    %{s | tracker: Map.delete(t, ref)}
  end

  defp report_metrics(%{counts: counts, opts: opts} = s) do
    import Fact.Influx, only: [write: 2]
    import Helen.Time.Helper, only: [unix_now: 1]

    datapoint_map = %{
      points: [
        %{
          measurement: "broom",
          fields: Enum.into(counts, %{}),
          tags: %{mod: Atom.to_string(opts[:module])},
          timestamp: unix_now(:nanosecond)
        }
      ]
    }

    %{s | metrics_rc: write(datapoint_map, precision: :nanosecond)}
  end

  defp schedule_metrics(%{opts: opts} = state) do
    import Helen.Time.Helper, only: [to_ms: 2]

    cancel_timer_if_needed = fn
      %{metrics_timer: x} = s when is_reference(x) ->
        Process.cancel_timer(x)
        %{s | metrics_timer: :canceled}

      s ->
        s
    end

    start_timer = fn x -> Process.send_after(self(), :report_metrics, to_ms(x, "P365D")) end

    case {opts[:metrics], cancel_timer_if_needed.(state)} do
      {x, s} when is_binary(x) -> %{s | metrics_timer: start_timer.(x)}
      {_, s} -> s
    end
  end

  defp store_update_error(%{errors: e} = s, ref, error) do
    %{s | errors: Map.put(e, ref, error)} |> increment_count(:errors)
  end

  defp noreply(s), do: {:noreply, s}
  defp reply(%{tracker: _} = s, res), do: {:reply, res, s}
  defp reply(res, %{tracker: _} = s), do: {:reply, res, s}
  defp reply_ok(s), do: {:ok, s}
end
