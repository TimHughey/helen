defmodule Switch.Payload do
  alias Switch.DB.Alias, as: Schema

  def create_cmd(%Schema{device: d} = a, cmd, opts) when is_list(opts) do
    import Helen.Time.Helper, only: [unix_now: 1]

    # default to the host ack'ing rhe command
    ack = opts[:ack] || :host

    %{
      payload: "switch state",
      mtime: unix_now(:second),
      host: d.host,
      device: d.device,
      states: make_state_map_list(a, cmd),
      refid: opts[:refid],
      ack: ack == :host
    }
  end

  # inbound payloads
  # (1 of 2) entry point for the make_cmd_from_state pipeline
  def make_cmd_from_state(sm, %Schema{} = a) when is_map(sm) do
    map_cmd_or_state(sm) |> make_cmd_from_state(a)
  end

  # (2 of 2) map :on or :off
  def make_cmd_from_state({cmd, sm}, _a) when cmd in [:off, :on] do
    put_in_state_map(sm, state: map_cmd_or_state(cmd))
  end

  # outbound payloads
  def make_state_map_list(%Schema{pio: pio}, cmd) do
    %{state: map_cmd_or_state(cmd), pio: pio} |> List.wrap()
  end

  # (1 of 2) when passed an actual state convert it to the cmd type and return {cmd, accumulator}
  def map_cmd_or_state(%{state: state} = sm) do
    {map_cmd_or_state(state), sm}
  end

  # (2 od 2) switches can only be on or off
  def map_cmd_or_state(x) do
    case x do
      :off -> false
      false -> :off
      :on -> true
      true -> :on
    end
  end

  def put_in_state_map(sm, l) when is_list(l) do
    for kv <- l, reduce: sm do
      acc -> put_in_state_map(acc, kv)
    end
  end

  def put_in_state_map(sm, {k, v}) do
    put_in(sm, [k], v)
  end

  def send_cmd(%Schema{} = a, cmd, opts) do
    create_cmd(a, cmd, opts) |> Mqtt.publish(opts)
  end
end
