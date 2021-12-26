defmodule Carol do
  @moduledoc """
  Carol controls equipment using a daily schedule
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Carol

      # otp_app = Keyword.fetch!(opts, :otp_app)
      # instances = Application.compile_env(otp_app, :instances, []) |> Keyword.keys()

      {otp_app} = Carol.Supervisor.compile_config(opts)

      @otp_app otp_app

      def config do
        {:ok, config} = Carol.Supervisor.runtime_config(@otp_app, __MODULE__, [])
        config
      end

      # NOTE: Supervisor child_spec
      @doc false
      def child_spec(opts) do
        config = config()

        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [config]},
          type: :supervisor
        }
      end

      def instances do
        Keyword.get(config(), :instances, []) |> Keyword.keys() |> Enum.sort()
      end

      def start_link(opts \\ []) do
        Carol.Supervisor.start_link({@otp_app, __MODULE__}, opts)
      end

      @status_def_opts [format: :humanized]
      def status(instance, opts \\ @status_def_opts) do
        which_children()
        |> Carol.call_fuzzy(instance, {:status, opts})
        |> Carol.status_post_process()
      end

      def which_children, do: Supervisor.which_children(__MODULE__)
    end
  end

  @callback config :: list()
  @callback instances :: list()

  @doc """
  Safely call a `Carol` server instance
  """
  @doc since: "0.2.1"
  def call(server, msg) when is_atom(server) or is_pid(server) do
    Carol.Server.call(server, msg)
  end

  @doc since: "0.3.0"
  def call_fuzzy(children, instance, args) do
    case find_instance_fuzzy(children, instance) do
      [{id, _pid, _display_name}] -> call(id, args)
      [] -> {:no_server, instance}
      [_ | _] = x -> {:multiple_matches, Enum.map(x, fn {_, _, name} -> name end)}
    end
  end

  # NOTE: pause/2, restart/2 and resume/2 accept a second argument to
  # maintain consistency with other functions

  @doc """
  Pause the server

  Pauses the server by unregistering for equipment notifies
  """
  @doc since: "0.2.8"
  def pause(server, _opts), do: Carol.call(server, :pause)

  @doc """
  Active episode id

  Returns
  """
  @doc since: "0.3.0"
  def active_episode(server), do: Carol.call(server, :active_id)

  @doc """
  Restart the server

  Exits with `{:stop, :normal, state}`, then restarted by Supervisor
  """
  @doc since: "0.2.8"
  def restart(server, _opts), do: Carol.call(server, :restart)

  @doc """
  Resume the server

  Resumes the server by registering for equipment notifies
  """
  @doc since: "0.2.8"
  def resume(server, _opts), do: Carol.call(server, :resume)

  @doc """
  Return the `State` of a `Carol` server instance

  Accepts a list of opts to limit/filter the fields to return.

  ## Options

  * `[]` - empty list for available fields
  * `[:all]` - all fields
  * `[:list]` - list of available fields (as as `[]`)
  * `[field]` - contents of a specific field
  * `[field, ...]` - only the listed fields

  """
  @doc since: "0.2.6"
  def state(server, args) do
    state_map = Carol.call(server, :state)

    case args do
      :all -> state_map
      x when x == [] or x == :keys -> Map.keys(state_map)
      [x | _] = want_keys when is_atom(x) -> Map.take(state_map, want_keys)
      key when is_atom(key) -> Map.get(state_map, key, {:unknown_key, key})
      _ -> {:unknown_args, args}
    end
    |> assemble_reply()
  end

  @doc since: "0.3.0"
  def status(server, opts \\ [format: :humanized]) do
    call(server, {:status, opts})
  end

  @doc false
  def status_post_process(results) do
    case results do
      [x | _] when is_binary(x) -> Enum.join(results, "\n") |> IO.puts()
      _ -> results
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp assemble_reply(reply) do
    case reply do
      x when is_struct(x) -> Map.from_struct(reply)
      x when is_map(x) -> Enum.into(reply, []) |> assemble_reply()
      [x | _] when is_binary(x) -> reply
      x when is_list(x) -> Enum.sort(reply)
      _ -> reply
    end
  end

  defp find_instance_fuzzy(children, instance) do
    for {id, pid, :worker, _} <- children, reduce: [] do
      acc ->
        case Carol.Instance.match_fuzzy(id, instance) do
          {:ok, display_name} -> [{id, pid, display_name} | acc]
          :no_match -> acc
        end
    end
  end
end
