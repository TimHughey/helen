defmodule Lights.Helpers do
  @moduledoc false

  @fallback_log_invalid_ms 5 * 60 * 1000
  @fallback_run_interval_ms 1000
  @fallback_timeout_ms 2 * 1000
  @fallback_timezone "Etc/UTC"
  @mod_parts Module.split(__MODULE__)

  def get_in_opts(s, what, fallback \\ nil) do
    get_in(s, [Access.key(:opts, %{}), what]) || fallback
  end

  def get_log_invalid(s) do
    get_in_opts(s, :invalid_log) |> parse_duration(@fallback_log_invalid_ms)
  end

  def get_loop_timeout(s) do
    get_in_opts(s, :timeout) |> parse_duration(@fallback_timeout_ms)
  end

  def get_timeouts(s) do
    get_in(s, [:timeout]) || :none
  end

  # token
  def change_token(s), do: update_in(s, [:token], fn x -> x + 1 end)
  def token(s), do: get_in(s, [:token])

  def now(s) do
    get_in_opts(s, :tz, @fallback_timezone) |> Timex.now()
  end

  def parse_duration(duration, fallback) do
    import Timex.Duration, only: [parse: 1, to_milliseconds: 2]

    case parse(duration) do
      {:ok, x} -> to_milliseconds(x, truncate: true)
      _x -> fallback
    end
  end

  def pretty(anything), do: "\n#{inspect(anything, pretty: true)}"

  def put_in_run(s, what, val) do
    put_in(s, [Access.key(:run, %{}), what], val)
  end

  def run_interval(s) do
    get_in_opts(s, :run_interval) |> parse_duration(@fallback_run_interval_ms)
  end

  defp update_last(s, what) do
    update_in(s, [Access.key(what, %{}), :last], fn _x -> now(s) end)
    |> update_in([what, Access.key(:count, 0)], fn x -> x + 1 end)
  end

  def update_last_run(s), do: update_last(s, :run)
  def update_last_timeout(s), do: update_last(s, :timeout)

  # GenServer Replies
  def noreply(s), do: {:noreply, s, get_loop_timeout(s)}
  def reply(val, s), do: {:reply, val, s, get_loop_timeout(s)}

  def server_mod(args) do
    get_in(args, [:mod]) || Module.concat([hd(@mod_parts), "Server"])
  end

  def server_name(args) do
    get_in(args, [:name]) || server_mod(args)
  end
end
