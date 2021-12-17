defmodule Carol do
  @moduledoc """
  Carol API for controlling a server instance
  """

  @doc """
  Safely call a `Carol` server instance
  """
  @doc since: "0.2.1"
  def call(server, msg) when is_atom(server) do
    Carol.Server.call(server, msg)
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
  Return the `Program` from a `Carol` instance

  Accepts a list of opts to select the `Program` and filter the fields
  returned.

  """
  @doc since: "0.2.6"
  def program(server, opts) when is_list(opts) do
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{id: id, params: true} -> %{program: id, cmd: true, params: true}
    end
    |> then(fn msg -> Carol.call(server, msg) end)
  end

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
  def state(server, want_keys) when is_list(want_keys) do
    state = Carol.Server.call(server, :state)

    case want_keys do
      [] -> Map.keys(state)
      [:all] -> state
      [:list] -> Map.keys(state)
      [key] -> Map.get(state, key)
      _ -> Map.take(state, want_keys)
    end
    |> Enum.into([])
  end
end
