defmodule Switch.States do
  require Logger

  alias Switch.DB.{Alias, Device}

  # accepts an inbound msg
  # returns the msg with the results of applying the state maps in the inbound msg to the
  # device aliases (as needed)
  def inbound_msg(in_msg) do
    case in_msg do
      %{states: []} -> put_states_rc(in_msg, {:failed, "inbound msg states == []"})
      %{states: in_sm, device: {:ok, d}} -> apply_state_maps(d, in_sm) |> put_states_rc(in_msg)
      _ -> put_states_rc(in_msg, {:failed, "inbound msg :state key not found or device update failed"})
    end
  end

  defp apply_state_maps(%Device{} = d, in_sm) do
    # find the state map from the list of states for a specific pio
    find_state_map = fn pio ->
      Enum.find(in_sm, fn
        %{pio: sm_pio, cmd: c} when sm_pio == pio and is_binary(c) -> true
        _ -> false
      end)
    end

    # only process inbound state maps for known aliases
    for %Alias{} = a <- d.aliases do
      changes = find_state_map.(a.pio)

      case Alias.apply_changes(a, changes) do
        {:ok, %Alias{} = x} -> [name: x.name, success: true, cmd: x.cmd]
        {:error, text} -> [name: a.name, success: false, error: text]
      end
    end
  end

  # (1 of 2) just put whatever is passed (typically an failure)
  defp put_states_rc(msg, rc) when is_map(msg), do: put_in(msg, [:states_rc], rc)

  # (2 of 2) examine the results list and determine an overall rc
  defp put_states_rc(results, msg) when is_list(results) do
    rc_from_result = fn rc, x ->
      case {rc, x[:success]} do
        {:ok, true} -> :ok
        {:ok, false} -> :failed
      end
    end

    # 1. delete the processed states
    # 2. add states_rc for final validation
    msg = Map.delete(msg, :states) |> put_in([:states_rc], {:ok, []})

    for result <- results, reduce: msg do
      # found an error, skip the remaining results
      %{states_rc: {rc, acc}} = msg ->
        %{msg | states_rc: {rc_from_result.(rc, result), [acc, result] |> List.flatten()}}
    end
  end
end
