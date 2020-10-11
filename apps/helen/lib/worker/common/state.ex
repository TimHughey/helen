defmodule Helen.Worker.State.Common do
  @moduledoc false

  import List, only: [flatten: 1]
  import Map, only: [put_new: 3]

  def base_opt(state, path \\ []),
    do: get_in(state, flatten([:opts, :base, path]))

  def change_token(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_in([:token], fn _x -> make_ref() end)
    |> update_in([:token_at], fn _x -> utc_now() end)
  end

  def faults_map(state), do: faults_get(state, [])

  def faults?(state) do
    case faults_get(state, []) do
      %{init: %{}} -> true
      _x -> false
    end
  end

  def faults_get(state, what) do
    get_in(state, flatten([:logic, :faults, what]))
  end

  def ready?(state), do: server_mode(state) == :ready

  def first_mode(state),
    do: opts_get(state, [:base, :first_mode]) || :none

  def last_timeout(%{lasts: %{timeout: last_timeout}} = state) do
    tz = opts(state, :timezone) || "America/New_York"

    case last_timeout do
      :never -> :never
      %DateTime{} = last_timeout -> Timex.to_datetime(last_timeout, tz)
      _unmatched -> :unknown
    end
  end

  def loop_timeout(state) do
    import Helen.Time.Helper, only: [to_ms: 1]

    timeout = base_opt(state, [:timeout]) || "PT30.0S"

    to_ms(timeout)
  end

  def not_ready?(state), do: not ready?(state)

  def opts(state, what) when not is_nil(what) and is_atom(what) do
    case what do
      :runtime -> get_in(state, [:opts])
      :server_mode -> get_in(state, [:opts, :base, :server_mode])
      what -> get_in(state, [:opts, what])
    end
  end

  def opts_get(state, what \\ []), do: get_in(state, flatten([:opts, what]))
  def opts_mode_names(state), do: opts_get(state, :modes) |> Map.keys()

  def server_get(state, what), do: get_in(state, flatten([:server, what]))

  def server_mode(state, mode \\ nil) do
    # ensure the server map exists in the state
    state =
      put_new(state, :server, %{
        mode: :ready,
        standby_reason: :none,
        faults: %{}
      })

    case mode do
      nil -> server_get(state, :mode)
      mode when mode in [:ready, :standby] -> server_put(state, :mode, mode)
      _unmatched -> state
    end
  end

  def server_put(state, what, val),
    do: put_in(state, flatten([:server, what]), val)

  def standby_reason(state), do: server_mode(state)

  def standby_reason_set(state, reason) do
    case standby_reason(state) do
      :standby -> server_put(state, :standby_reason, reason)
      :active -> server_put(state, :standby_reason, :none)
      _unmatched -> server_put(state, :standby_reason, :unknown)
    end
  end

  def startup_mode(state), do: base_opt(state, :start_mode) || :none

  def timeouts(%{timeouts: %{count: count}}), do: count

  def token(%{token: token}), do: token

  def update_last_timeout(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> put_in([:timeouts, :last], utc_now())
    |> update_in([:timeouts, :count], fn x -> x + 1 end)
  end

  def worker_name(state), do: opts_get(state, [:base, :worker_name])
end
