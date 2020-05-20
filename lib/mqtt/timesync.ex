defmodule Mqtt.Timesync do
  @moduledoc false

  require Logger
  use Task

  import TimeSupport, only: [ms: 1, unix_now: 1]

  def run(opts) do
    # reasonable defaults if configuration is not set
    frequency = Map.get(opts, :frequency, {:mins, 1})
    loops = Map.get(opts, :loops, 0)
    forever = Map.get(opts, :forever, true)
    log = Map.get(opts, :log, false)
    single = Map.get(opts, :single, false)
    client_id = Map.get(opts, :client_id, "bad-client")
    feed = [Map.get(opts, :feed, "foobar"), "timesync"] |> Enum.join("/")

    # construct the timesync message and publish it

    res = Tortoise.publish(client_id, feed, cmd_payload(), [])

    log && Logger.info(["published timesync ", inspect(res, pretty: true)])

    opts = %{opts | loops: opts.loops - 1}

    cond do
      single ->
        :ok

      forever or loops - 1 > 0 ->
        :timer.sleep(ms(frequency))
        run(opts)

      true ->
        :executed_requested_loops
    end
  end

  def send do
    run(%{single: true})
  end

  def cmd_payload do
    import Msgpax, only: [pack!: 1]
    %{mtome: unix_now(:second), payload: "timesync"} |> pack!()
  end
end
