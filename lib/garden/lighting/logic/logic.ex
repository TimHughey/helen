defmodule Garden.Lighting.Logic do
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

  def validate_all_durations(%{opts: opts} = _state) do
    validate_duration_r(opts, true)
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
      {{k, d}, acc} when k in [:run_for, :for] and is_binary(d) ->
        acc && valid_ms?(d)

      # not a tuple of interest, keep going
      {_no_interest, acc} ->
        acc
    end
  end

  # defp validate_opts(%{init_fault: _} = state), do: state
  # # TODO implement!!
  # defp validate_opts(state), do: state
end
