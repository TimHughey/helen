defmodule Switch.States do
  alias Switch.DB.{Alias, Command, Device}
  alias Switch.Payload

  # (1 of 2) this is a cmdack message
  def ack_if_needed(%{cmdack: true, device: {:ok, %Device{}}} = msg) do
    Command.ack(msg)
  end

  # (2 of 2) not a cmd ack message, nothing to do
  def ack_if_needed(msg), do: put_in(msg, [:cmd_rc], [])

  # (1 of 2) states are empty
  def apply_states(%{states: []} = msg), do: put_results(msg, {:failed, "states == []"})

  # (2 of 3) states not present
  def apply_states(%{} = msg) when not is_map_key(msg, :states),
    do: put_results(msg, {:failed, "msg does not contain :states"})

  # (3 of 3) states are present but device doesn't have any aliases
  def apply_states(%{device: {:ok, %Device{aliases: []}}} = msg), do: put_results(msg, [])

  # (4 of 4) states present, device has aliases, store the state
  def apply_states(%{states: states, device: {:ok, %Device{aliases: aliases}}} = msg) do
    results =
      for %Alias{pio: alias_pio} = a <- aliases do
        remote_cmd = get_state_map(states, alias_pio) |> Payload.make_cmd_from_state(a)
        Alias.apply_reported_cmd(a, remote_cmd)
      end

    put_in(msg, [:apply_states], results)
  end

  # find the state list entry that matches this alias
  def get_state_map(states, pio) do
    Enum.find(states, fn
      %{pio: x} -> x == pio
      _x -> false
    end)
  end

  def put_results(msg, rc), do: put_in(msg, [:states_rc], rc)

  def incoming_states(msg) do
    put_in(msg, [:states_rc], {:pending, []}) |> ack_if_needed() |> apply_states()
  end
end
