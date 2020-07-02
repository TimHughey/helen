defmodule Reef.Captain.Status do
  @moduledoc """
  Creates a binary representation of the Reef Fill Status
  """

  alias Reef.Captain.Server

  @doc false
  def msg do
    with %{server_mode: :active, reef_mode: reef_mode} = state <-
           Server.x_state() do
      case reef_mode do
        :fill -> fill(state)
        :keep_fresh -> keep_fresh(state)
        :mix_salt -> mix_salt(state)
        :prep_for_change -> prep_for_change(state)
        :ready -> ready(state)
      end
    else
      :DOWN ->
        """
        Reef Captain is DOWN
        """

      %{server_mode: :standby} ->
        """
        Reef Captain is in Standby Mode
        """
    end
  end

  @doc false
  def msg(reef_mode) when is_atom(reef_mode) do
    with %{server_mode: :active} = state <- Server.x_state() do
      case reef_mode do
        :fill -> fill(state)
        :keep_fresh -> keep_fresh(state)
        :mix_salt -> mix_salt(state)
        :prep_for_change -> prep_for_change(state)
      end
    else
      :DOWN ->
        """
        Reef Captain is DOWN
        """

      %{server_mode: :standby} ->
        """
        Reef Captain is in Standby Mode
        """
    end
  end

  def fill(%{fill: map}) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case map[:status] do
      :ready ->
        """
        Reef Fill is Ready
        """

      :completed ->
        """
        Reef Fill Completed, elapsed time #{to_binary(map[:elapsed])}.

           Started: #{to_binary(map[:started_at])}
          Finished: #{to_binary(map[:finished_at])}
        """

      :in_progress ->
        """
        Reef Fill In-Progress, elapsed time #{to_binary(map[:elapsed])}.

                Started: #{to_binary(map[:started_at])}
        Expected Finish: #{to_binary(map[:will_finish_by])}

              Executing: #{inspect(map[:active_step])}
              Remaining: #{inspect(map[:steps_to_execute])}
                Command: #{inspect(map[:step][:cmd])}
                Elapsed: #{to_binary(map[:step][:elapsed])}
                 Cycles: #{step_cycles(map)}
        """
    end
  end

  def keep_fresh(%{keep_fresh: map}) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case map[:status] do
      :ready ->
        """
        Reef Keep Fresh is Ready
        """

      :completed ->
        """
        Reef Keep Fresh Completed, elapsed time #{to_binary(map[:elapsed])}.

           Started: #{to_binary(map[:started_at])}
          Finished: #{to_binary(map[:finished_at])}
        """

      :running ->
        active_step = map[:active_step]

        """
        Reef Keep Fresh Running, elapsed time #{to_binary(map[:elapsed])}.

                Started: #{to_binary(map[:started_at])}

              Executing: #{inspect(active_step)}
                Command: #{inspect(map[:step][:cmd])}
                Elapsed: #{to_binary(map[:step][:elapsed])}
                 Cycles: #{step_cycles(map)}
        """
    end
  end

  def mix_salt(%{mix_salt: map}) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case map[:status] do
      :ready ->
        """
        Reef Mix Salt is Ready
        """

      :completed ->
        """
        Reef Mix Salt Completed, elapsed time #{to_binary(map[:elapsed])}.

           Started: #{to_binary(map[:started_at])}
          Finished: #{to_binary(map[:finished_at])}
        """

      :in_progress ->
        active_step = map[:active_step]

        """
        Reef Mix Salt In-Progress, elapsed time #{to_binary(map[:elapsed])}.

                   Started: #{to_binary(map[:started_at])}
           Expected Finish: #{to_binary(map[:will_finish_by])}

            Executing Step: #{active_step}
           Remaining Steps: #{inspect(map[:steps_to_execute])}
                   Elapsed: #{to_binary(map[:step][:elapsed])}
                    Cycles: #{step_cycles(map)}

         Executing Command: #{inspect(map[:step][:cmd])}
        Remaining Commands: #{inspect(map[:step][:cmds_to_execute])}

        """
    end
  end

  def prep_for_change(%{prep_for_change: map}) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case map[:status] do
      :ready ->
        """
        Reef Prep For Change is Ready
        """

      :completed ->
        """
        Reef Prep For Change Completed, elapsed time #{to_binary(map[:elapsed])}.

           Started: #{to_binary(map[:started_at])}
          Finished: #{to_binary(map[:finished_at])}
        """

      :running ->
        dt_temp = Reef.DisplayTank.Temp.temperature()
        mt_temp = Reef.MixTank.Temp.temperature()

        diff_temp = calculate_temp_difference(dt_temp, mt_temp)

        """
        Reef Prep For Change Running, elapsed time #{to_binary(map[:elapsed])}.

                   Started: #{to_binary(map[:started_at])}

        DisplayTank Temp F: #{inspect(dt_temp)}
            MixTank Temp F: #{inspect(mt_temp)}
                 Temp Diff: #{inspect(diff_temp)}

                 Executing: #{inspect(map[:active_step])}
                 Remaining: #{inspect(map[:steps_to_execute])}
                   Command: #{inspect(map[:step][:cmd])}
                   Elapsed: #{to_binary(map[:step][:elapsed])}
                    Cycles: #{step_cycles(map)}
        """
    end
  end

  def ready(_state) do
    """
    Reef Captain is Ready
    """
  end

  defp calculate_temp_difference(t1, t2)
       when is_number(t1) and is_number(t2) do
    abs(t1 - t2) |> Float.round(1)
  end

  defp calculate_temp_difference(_t1, _t2), do: :initializing

  defp step_cycles(%{active_step: active_step} = reef_mode) do
    get_in(reef_mode, [:cycles, active_step]) |> inspect()
  end
end
