defmodule GenDevice.State do
  @moduledoc false

  import Helen.Worker.State.Common

  import List, only: [flatten: 1]
  import Map, only: [put_new: 3]

  def action_cmd(state), do: action_get(state, :worker_cmd)

  def action_for(state), do: action_get(state, :for) || :none

  def action_get(state, what),
    do: get_in(state, flatten([:inflight, :action, what]))

  def action_then_cmd(state), do: action_get(state, :at_cmd_finish)

  def at_cmd_finished?(state), do: notify?(state, :at_finish)

  def at_cmd_start?(state), do: notify?(state, :at_start)

  def cmd_for(state), do: action_get(state, :for) || :none

  def device_name(state), do: top_get(state, :device_name)

  def inflight_adjust_result(state, cmd, rc) do
    import Helen.Time.Helper, only: [utc_now: 0]

    inflight_put(state, :adjust, %{at: utc_now(), cmd: cmd, rc: rc})
  end

  def inflight_copy_token(state),
    do: inflight_put(state, [:token], token(state))

  def inflight_get(state, what),
    do: get_in(state, flatten([:inflight, :action, :gen_device, what]))

  def inflight_move_to_lasts(state) do
    lasts_put(state, :inflight, get_in(state, [:inflight]))
    |> put_in([:inflight], %{})
  end

  def lasts_get(state, what), do: get_in(state, flatten([:lasts, what]))

  def lasts_put(state, what, val),
    do: put_new(state, :lasts, %{}) |> put_in(flatten([:lasts, what]), val)

  def inflight_put(state, what, val) do
    state
    |> update_in([:inflight], fn x -> put_new(x, :action, %{}) end)
    |> update_in([:inflight, :action], fn x -> put_new(x, :gen_device, %{}) end)
    |> put_in(flatten([:inflight, :action, :gen_device, what]), val)
  end

  def inflight_status(state, status \\ nil) do
    if is_nil(status) do
      inflight_get(state, :status) ||
        lasts_get(state, [:inflight, :action, :gen_device, :status]) ||
        :none
    else
      inflight_put(state, :status, status)
    end
  end

  def inflight_store(state, action) do
    put_new(state, :inflight, %{}) |> put_in([:inflight, :action], action)
  end

  def inflight_token(state), do: inflight_get(state, :token)

  def inflight_update(state, what, func) do
    update_in(state, flatten([:inflight, :action, what]), func)
  end

  def module(state), do: top_get(state, :module)

  def msg_ref(state), do: inflight_get(state, :msg_ref)
  def msg_type(state), do: action_get(state, :msg_type)
  def notify?(state, at), do: action_get(state, [:notify, at]) || false

  def reply_to(state),
    do: action_get(state, :reply_to) || inflight_get(state, :from_pid)

  def run_for_expired?(state),
    do: inflight_get(state, :run_for_expired?) || false

  def top_get(state, what), do: get_in(state, flatten([what]))
end
