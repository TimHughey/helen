defmodule Reef.FirstMate.Status do
  @moduledoc """
  Creates a binary representation of the Reef Fill Status
  """

  def msg(%{} = state) do
    state
    |> header()
    |> summary()
    |> detail()
    |> footer()
    |> IO.iodata_to_binary()
  end

  defp header(%{module: mod, state_at: state_at} = state) do
    import Helen.Time.Helper, only: [to_binary: 1]

    mod_parts = Module.split(mod)
    worker_name = Enum.slice(mod_parts, 1, 1) |> hd()
    worker_mode = mode_to_binary(state)

    {state,
     """
     #{to_binary(state_at)}

              Worker: #{worker_name}
                Mode: #{worker_mode}
     """}
  end

  defp summary({%{worker_mode: worker_mode} = state, msg}) do
    import Helen.Time.Helper, only: [to_binary: 1]
    status = get_in(state, [worker_mode, :status])
    elapsed = get_in(state, [worker_mode, :elapsed])
    started_at = get_in(state, [worker_mode, :started_at])
    will_finish_by = get_in(state, [worker_mode, :will_finish_by])

    {state,
     [
       msg,
       case {started_at, will_finish_by} do
         {at, by} when is_struct(at) and is_struct(by) ->
           """

                    Status: #{status |> Atom.to_string() |> String.upcase()}
                Started At: #{to_binary(at)}
           Expected Finish: #{to_binary(by)}

                   Elapsed: #{to_binary(elapsed)}

           """

         {at, nil} when is_struct(at) ->
           """

                    Status: #{status |> Atom.to_string()}
                Started At: #{to_binary(at)}

                   Elapsed: #{to_binary(elapsed)}

           """

         _no_match ->
           ""
       end
     ]}
  end

  defp detail({state, msg}) do
    {state, [msg]}
  end

  defp footer({_state, msg}) do
    msg
  end

  defp mode_to_binary(state) do
    for part <- Atom.to_string(state[:worker_mode]) |> String.split("_") do
      String.capitalize(part)
    end
    |> Enum.join(" ")
  end

  # @doc false
  # def msg do
  #   with %{server_mode: :active, reef_mode: reef_mode} = state <-
  #          Server.x_state() do
  #     case reef_mode do
  #       :fill -> fill(state)
  #       :keep_fresh -> keep_fresh(state)
  #       :mix_salt -> mix_salt(state)
  #       :prep_for_change -> prep_for_change(state)
  #       :water_change -> water_change(state)
  #       :ready -> ready(state)
  #     end
  #   else
  #     :DOWN ->
  #       """
  #       Reef Captain is DOWN
  #       """
  #
  #     %{server_mode: :standby} ->
  #       """
  #       Reef Captain is in Standby Mode
  #       """
  #   end
  # end
  #
  # @doc false
  # def msg(reef_mode) when is_atom(reef_mode) do
  #   with %{server_mode: :active} = state <- Server.x_state() do
  #     case reef_mode do
  #       :fill -> fill(state)
  #       :keep_fresh -> keep_fresh(state)
  #       :mix_salt -> mix_salt(state)
  #       :prep_for_change -> prep_for_change(state)
  #     end
  #   else
  #     :DOWN ->
  #       """
  #       Reef Captain is DOWN
  #       """
  #
  #     %{server_mode: :standby} ->
  #       """
  #       Reef Captain is in Standby Mode
  #       """
  #   end
  # end
  #
  # def fill(%{fill: map}) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   case map[:status] do
  #     :ready ->
  #       """
  #       Reef Fill is Ready
  #       """
  #
  #     :completed ->
  #       """
  #       Reef Fill Completed, elapsed time #{to_binary(map[:elapsed])}.
  #
  #          Started: #{to_binary(map[:started_at])}
  #         Finished: #{to_binary(map[:finished_at])}
  #       """
  #
  #     :running ->
  #       """
  #       Reef Fill In-Progress, elapsed time #{to_binary(map[:elapsed])}.
  #
  #               Started: #{to_binary(map[:started_at])}
  #       Expected Finish: #{to_binary(map[:will_finish_by])}
  #
  #             Executing: #{inspect(map[:active_step])}
  #             Remaining: #{inspect(map[:steps_to_execute])}
  #               Command: #{inspect(map[:step][:cmd])}
  #               Elapsed: #{to_binary(map[:step][:elapsed])}
  #                Cycles: #{step_cycles(map)}
  #       """
  #   end
  # end
  #
  # def keep_fresh(%{keep_fresh: map}) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   case map[:status] do
  #     :ready ->
  #       """
  #       Reef Keep Fresh is Ready
  #       """
  #
  #     :completed ->
  #       """
  #       Reef Keep Fresh Completed, elapsed time #{to_binary(map[:elapsed])}.
  #
  #          Started: #{to_binary(map[:started_at])}
  #         Finished: #{to_binary(map[:finished_at])}
  #       """
  #
  #     :running ->
  #       active_step = map[:active_step]
  #
  #       """
  #       Reef Keep Fresh Running, elapsed time #{to_binary(map[:elapsed])}.
  #
  #               Started: #{to_binary(map[:started_at])}
  #
  #             Executing: #{inspect(active_step)}
  #               Command: #{inspect(map[:step][:cmd])}
  #               Elapsed: #{to_binary(map[:step][:elapsed])}
  #                Cycles: #{step_cycles(map)}
  #       """
  #   end
  # end
  #
  # def mix_salt(%{mix_salt: map}) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   case map[:status] do
  #     :ready ->
  #       """
  #       Reef Mix Salt is Ready
  #       """
  #
  #     :completed ->
  #       """
  #       Reef Mix Salt Completed, elapsed time #{to_binary(map[:elapsed])}.
  #
  #          Started: #{to_binary(map[:started_at])}
  #         Finished: #{to_binary(map[:finished_at])}
  #       """
  #
  #     :running ->
  #       active_step = map[:active_step]
  #
  #       """
  #       Reef Mix Salt In-Progress, elapsed time #{to_binary(map[:elapsed])}.
  #
  #                  Started: #{to_binary(map[:started_at])}
  #          Expected Finish: #{to_binary(map[:will_finish_by])}
  #
  #           Executing Step: #{active_step}
  #          Remaining Steps: #{inspect(map[:steps_to_execute])}
  #                  Elapsed: #{to_binary(map[:step][:elapsed])}
  #                   Cycles: #{step_cycles(map)}
  #
  #        Executing Command: #{inspect(map[:step][:cmd])}
  #       Remaining Commands: #{inspect(map[:step][:cmds_to_execute])}
  #
  #       """
  #   end
  # end
  #
  # def prep_for_change(%{prep_for_change: map}) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   case map[:status] do
  #     :ready ->
  #       """
  #       Reef Prep For Change is Ready
  #       """
  #
  #     :completed ->
  #       """
  #       Reef Prep For Change Completed, elapsed time #{to_binary(map[:elapsed])}.
  #
  #          Started: #{to_binary(map[:started_at])}
  #         Finished: #{to_binary(map[:finished_at])}
  #       """
  #
  #     :running ->
  #       dt_temp = Reef.DisplayTank.Temp.temperature()
  #       mt_temp = Reef.MixTank.Temp.temperature()
  #
  #       diff_temp = calculate_temp_difference(dt_temp, mt_temp)
  #
  #       """
  #       Reef Prep For Change Running, elapsed time #{to_binary(map[:elapsed])}.
  #
  #                  Started: #{to_binary(map[:started_at])}
  #
  #       DisplayTank Temp F: #{inspect(dt_temp)}
  #           MixTank Temp F: #{inspect(mt_temp)}
  #                Temp Diff: #{inspect(diff_temp)}
  #
  #                Executing: #{inspect(map[:active_step])}
  #                Remaining: #{inspect(map[:steps_to_execute])}
  #                  Command: #{inspect(map[:step][:cmd])}
  #                  Elapsed: #{to_binary(map[:step][:elapsed])}
  #                   Cycles: #{step_cycles(map)}
  #       """
  #   end
  # end
  #
  # def water_change(%{water_change: map}) do
  #   import Helen.Time.Helper, only: [to_binary: 1]
  #
  #   case map[:status] do
  #     :ready ->
  #       """
  #       Reef Water Change is Ready
  #       """
  #
  #     :completed ->
  #       """
  #       Reef Water Change Completed, elapsed time #{to_binary(map[:elapsed])}.
  #
  #          Started: #{to_binary(map[:started_at])}
  #         Finished: #{to_binary(map[:finished_at])}
  #       """
  #
  #     :running ->
  #       dt_temp = Reef.DisplayTank.Temp.temperature()
  #       mt_temp = Reef.MixTank.Temp.temperature()
  #
  #       diff_temp = calculate_temp_difference(dt_temp, mt_temp)
  #
  #       """
  #       Reef Water Change Running, elapsed time #{to_binary(map[:elapsed])}.
  #
  #                  Started: #{to_binary(map[:started_at])}
  #
  #       DisplayTank Temp F: #{inspect(dt_temp)}
  #           MixTank Temp F: #{inspect(mt_temp)}
  #                Temp Diff: #{inspect(diff_temp)}
  #
  #                Executing: #{inspect(map[:active_step])}
  #                Remaining: #{inspect(map[:steps_to_execute])}
  #                  Command: #{inspect(map[:step][:cmd])}
  #                  Elapsed: #{to_binary(map[:step][:elapsed])}
  #                   Cycles: #{step_cycles(map)}
  #       """
  #   end
  # end
  #
  # def ready(_state) do
  #   """
  #   Reef Captain is Ready
  #   """
  # end
  #
  # defp calculate_temp_difference(t1, t2)
  #      when is_number(t1) and is_number(t2) do
  #   abs(t1 - t2) |> Float.round(1)
  # end
  #
  # defp calculate_temp_difference(_t1, _t2), do: :initializing
  #
  # defp step_cycles(%{active_step: active_step} = reef_mode) do
  #   get_in(reef_mode, [:cycles, active_step]) |> inspect()
  # end
end
