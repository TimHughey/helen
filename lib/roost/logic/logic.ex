defmodule Roost.Logic do
  def available_modes(%{opts: opts} = _state) do
    Keyword.drop(opts, [:__available__, :__version__])
    |> Keyword.keys()
    |> Enum.sort()
  end

  def change_token(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_in([:token], fn _x -> make_ref() end)
    |> update_in([:token_at], fn _x -> utc_now() end)
  end

  def init_precheck(state, worker_mode, override_opts) do
    state
    |> Map.drop([:init_fault])
    # we use the :pending key to build up the next reef command to
    # avoid conflicts if a reef command is running
    |> put_in([:pending], %{})
    |> put_in([:pending, :worker_mode], worker_mode)
    |> put_in([:pending, worker_mode], %{})
    |> confirm_worker_mode_exists(worker_mode)
    |> assemble_and_put_final_opts(override_opts)
    |> validate_opts()
    |> validate_durations()
  end

  def init_mode(%{init_fault: _} = state), do: state

  def init_mode(%{pending: %{worker_mode: worker_mode}} = state) do
    cmd_opts = get_in(state, [:pending, worker_mode, :opts])

    state
    |> put_in([:pending, worker_mode, :steps], cmd_opts[:steps])
    |> put_in([:pending, worker_mode, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([:pending, worker_mode, :step_devices], cmd_opts[:step_devices])
    |> build_device_last_cmds_map()
    |> note_delay_if_requested()
  end

  def step_device_to_mod(dev) do
    case dev do
      :handoff -> :handoff
      :disco_ball -> PulseWidth
      :el_entry -> PulseWidth
      :el_wire_dance_floor -> PulseWidth
      :lighting_dance_floor1 -> PulseWidth
      :lighting_dance_floor2 -> PulseWidth
    end
  end

  def validate_all_durations(%{opts: opts} = _state) do
    validate_duration_r(opts, true)
  end

  defp assemble_and_put_final_opts(
         %{pending: %{worker_mode: worker_mode}, opts: opts} = state,
         overrides
       ) do
    import DeepMerge, only: [deep_merge: 2]

    api_opts = [overrides] |> List.flatten()

    config_opts = get_in(opts, [:modes, worker_mode])
    final_opts = deep_merge(config_opts, api_opts)

    state
    |> put_in([:pending, worker_mode, :opts], %{})
    |> put_in([:pending, worker_mode, :opts], final_opts)
  end

  defp build_device_last_cmds_map(
         %{pending: %{worker_mode: worker_mode}} = state
       ) do
    state = put_in(state, [:pending, worker_mode, :device_last_cmds], %{})

    # :none is a special value that signifies no cmd messages are expected so
    # don't create a map entry
    for {_k, v} when v != :none <-
          get_in(state, [:pending, worker_mode, :step_devices]) || [],
        reduce: state do
      state ->
        cmd_map = %{
          off: %{at_finish: nil, at_start: nil},
          on: %{at_finish: nil, at_start: nil}
        }

        mod = step_device_to_mod(v)

        state
        |> put_in([:pending, worker_mode, :device_last_cmds, mod], cmd_map)
    end
  end

  defp confirm_worker_mode_exists(state, worker_mode) do
    known_worker_mode? = get_in(state, [:opts, :modes, worker_mode]) || false

    if known_worker_mode? do
      state |> put_in([:pending, :worker_mode], worker_mode)
    else
      state |> put_in([:init_fault], {:unknown_worker_mode, worker_mode})
    end
  end

  defp note_delay_if_requested(%{init_fault: _} = state), do: state

  defp note_delay_if_requested(%{pending: %{worker_mode: worker_mode}} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, valid_ms?: 1]

    opts = get_in(state, [:pending, worker_mode, :opts])

    case opts[:start_delay] do
      # just fine, no delay requested
      delay when is_nil(delay) ->
        state

      # delay requested, validate it then store if valid
      delay ->
        if valid_ms?(delay) do
          state
          # store the delay for pattern matching later
          |> put_in([:pending, :delay], to_ms(delay))
          # take out of opts to avoid cruf
          |> update_in([:pending, worker_mode, :opts], fn x ->
            Keyword.drop(x, [:start_delay])
          end)
        else
          state |> put_in([:init_fault], :invalid_delay)
        end
    end
  end

  defp validate_durations(%{init_fault: _} = state), do: state

  # primary entry point for validating durations
  defp validate_durations(%{pending: %{worker_mode: worker_mode}} = state) do
    opts = get_in(state, [:pending, worker_mode, :opts])

    # validate the opts with an initial accumulator of true so an empty
    # list is considered valid
    if validate_duration_r(opts, true),
      do: state,
      else: state |> put_in([:init_fault], :duration_validation_failed)
  end

  defp validate_duration_r(opts, acc) do
    import Helen.Time.Helper, only: [valid_ms?: 1]

    case {opts, acc} do
      # end of a list (or all list), simply return the acc
      {[], acc} ->
        acc

      # seen a bad duration, we're done
      {_, false} ->
        false

      # process the head (tuple) and the tail (a list or a tuple)
      {[head | tail], acc} ->
        acc && validate_duration_r(head, acc) &&
          validate_duration_r(tail, acc)

      # keep unfolding
      {{_, v}, acc} when is_list(v) ->
        acc && validate_duration_r(v, acc)

      # we have a tuple to check
      {{k, d}, acc} when k in [:before, :after, :timeout] and is_binary(d) ->
        acc && valid_ms?(d)

      # not a tuple of interest, keep going
      {_no_interest, acc} ->
        acc
    end
  end

  defp validate_opts(%{init_fault: _} = state), do: state
  # TODO implement!!
  defp validate_opts(state), do: state
end
