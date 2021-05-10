defmodule Switch.Execute do
  @moduledoc """
  Switch Execute Implementation

  Consolidated API for issuing all commands to a Switch device.

  This module consists of a series of execute functions that progressively
  validate the cmd to ultimately submit the cmd for execution.
  """

  alias Switch.DB.Alias
  alias Switch.Status

  @doc """
    Execute a command spec

    ### Options
      1. :lazy (boolean) - when true and status matches spec don't publish
      2. :force (boolean) - publish spec regardless of status
      2. :ignore_pending (boolean) - when true disregard pending status
      3. :ttl_ms (integer) - override Alias and Device ttl_ms
      4. :ack [:immediate, :host] - ack the spec immediately or wait for host ack

    ### Usage
      ```elixir

        map = %{name: "name", cmd: :on}, opts: [lazy: false, ttl_ms: 1000]}
        execute(map)

        cmd = %{pwm: "name", cmd: off}
        execute(cmd, ignore_pending: true)

      ```
  """
  @doc since: "0.9.9"
  # (1 of 9) permit a single arg that contains the cmd and optional opts
  def execute(%{opts: opts} = cmd) when is_map(cmd) do
    cmd = Map.delete(cmd, :opts)
    execute(cmd, opts)
  end

  # (2 of 9) accept a map without opts
  def execute(cmd) when is_map(cmd) do
    execute(cmd, [])
  end

  # (3 of 9) opts must be a map
  def execute(_cmd, opts) when not is_list(opts) do
    {:invalid_cmd, "opts must be a list"}
  end

  # (4 of 9) when cmd is an atom it must be supported
  def execute(%{cmd: cmd}, _opts) when is_atom(cmd) and cmd not in [:on, :off, :all_off] do
    {:invalid_cmd, "unrecognized cmd: #{inspect(cmd)}"}
  end

  # (5 of 9) cmd is missing the :name
  def execute(cmd, _opts) when is_map(cmd) and is_map_key(cmd, :name) == false do
    {:invalid_cmd, "cmd must contain key :name"}
  end

  # (6 of 9) validate the named alias exists by getting the current status
  def execute(%{name: name} = cmd, opts) when is_list(opts) do
    import Alias, only: [find: 1]
    import Status, only: [make_status: 2]

    # default to lazy if not specified
    opts = if opts[:lazy] == false, do: opts, else: opts ++ [lazy: true]

    case find(name) do
      %Alias{} = x -> execute(make_status(x, opts), x, cmd, opts)
      not_found -> not_found
    end
  end

  # (7 of 9) unmatched cmd
  def execute(cmd_map, _opts) do
    {:invalid_cmd, "cmd not recognized: #{inspect(cmd_map, pretty: true)}"}
  end

  # ok... we have a valid cmd and current status

  # (8 of 9) we have a Switch Alias and a validated cmd
  def execute(status, %Alias{} = a, cmd, opts) when is_map(status) do
    import Status, only: [compare: 3]

    force = opts[:lazy] == false || opts[:force] == true

    # compare/3 returns:
    # 1. tuple when conditions do not support execute (e.g. invalid, ttl_expired, pending)
    # 2. single atom for actual comparison result
    case compare(status, cmd, opts) do
      rc when is_tuple(rc) -> rc
      rc when rc == :equal and force -> execute(:needed, a, cmd, opts)
      rc when rc == :not_equal -> execute(:needed, a, cmd, opts)
      rc when rc == :equal -> {:ok, status}
    end
  end

  # (9 of 9) execute the cmd!
  def execute(:needed, %Alias{} = a, cmd, opts) do
    import Alias, only: [record_cmd: 3]

    record_cmd(a, cmd, opts)
  end
end
