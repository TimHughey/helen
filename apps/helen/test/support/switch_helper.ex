defmodule SwitchTestHelper do
  @moduledoc false

  alias Switch.DB.{Alias, Device}

  def cmd_to_boolean(cmd) do
    case cmd do
      :on -> true
      :off -> false
    end
  end

  def delete_default_device do
    case Switch.DB.Device.find(device_default()) do
      %Switch.DB.Device{} = x -> Repo.delete(x)
      _not_found -> nil
    end
  end

  def device_default, do: MsgTestHelper.device_default()

  def execute_cmd(%{execute: cmd, device_actual: device_actual} = ctx) do
    import MsgTestHelper, only: [process_msg: 2, switch_msg: 1]

    freshen(ctx)

    put_in(
      ctx,
      [:execute_rc],
      case Switch.execute(cmd) do
        {:pending, res} when is_list(res) ->
          %Alias{pio: alias_pio} = Switch.alias_find(get_in(cmd, [:name]))

          states =
            for %{pio: pio, state: state} <- extract_states(device_actual) do
              if pio == alias_pio,
                do: %{state: cmd_to_boolean(cmd[:cmd]), pio: pio},
                else: %{state: state, pio: pio}
            end

          if ctx[:ack] do
            opts = [
              device: device_actual.device,
              ack: true,
              refid: res[:refid],
              states: states
            ]

            switch_msg(opts)
            |> process_msg([])
          end

          res

        error ->
          error
      end
    )
  end

  def extract_states(%Device{states: states}) do
    for %{state: state, pio: pio} <- states do
      %{state: state, pio: pio}
    end
  end

  def freshen(%{device_actual: %Device{} = device_actual} = ctx) do
    import MsgTestHelper, only: [process_msg: 2, switch_msg: 1]

    states = extract_states(device_actual)

    put_in(
      ctx,
      [:freshen_results],
      switch_msg(states: states) |> process_msg([])
    )
  end

  def make_alias(
        %{pio: pio, alias_name: alias_name, device_actual: device_actual} = ctx
      ) do
    import Helen.Time.Helper, only: [unix_now: 0]
    import IO, only: [iodata_to_binary: 1]

    opts = [
      description: iodata_to_binary(["new alias ", inspect(unix_now())]),
      ttl_ms: ctx[:ttl_ms] || 1000
    ]

    pios = Device.pio_count(ctx[:device])
    %Device{device: device_default} = device_actual
    device_name = ctx[:device] || device_default

    put_in(
      ctx,
      [:alias_create],
      if pio == :any do
        for x <- 0..pios, reduce: false do
          false ->
            case Switch.alias_create(device_name, alias_name, x, opts) do
              res when is_list(res) ->
                if is_list(res[:created]), do: res, else: false

              _failed ->
                false
            end

          acc when is_list(acc) ->
            acc
        end
      else
        Switch.alias_create(device_name, alias_name, pio)
      end
    )
  end

  def make_switch(opts) do
    import MsgTestHelper, only: [process_msg: 2, switch_msg: 1]

    switch_msg(opts) |> process_msg([])
  end
end
