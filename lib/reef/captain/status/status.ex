defmodule Reef.Captain.Status do
  @moduledoc """
  Creates a binary representation of the Reef Fill Status
  """

  alias Reef.Captain.Server

  @doc false
  def msg(reef_mode) when is_atom(reef_mode) do
    with %{server_mode: :active} = state <- Server.state() do
      case reef_mode do
        :fill -> fill(state)
        :keep_fresh -> keep_fresh(state)
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

  def fill(%{fill: fill}) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case fill[:status] do
      :ready ->
        """
        Reef Fill is Ready
        """

      :completed ->
        """
        Reef Fill Completed, elapsed time #{to_binary(fill[:elapsed])}.

           Started: #{to_binary(fill[:started_at])}
          Finished: #{to_binary(fill[:finished_at])}
        """

      :in_progress ->
        """
        Reef Fill In-Progress, elapsed time #{to_binary(fill[:elapsed])}.

                Started: #{to_binary(fill[:started_at])}
        Expected Finish: #{to_binary(fill[:will_finish_by])}

              Executing: #{inspect(fill[:active_step])}
              Remaining: #{inspect(fill[:steps_to_execute] |> tl())}
                Command: #{inspect(fill[:step][:cmd])}
                Elapsed: #{to_binary(fill[:step][:elapsed])}
                 Cycles: #{inspect(fill[:step][:cycles])}
        """
    end
  end

  def keep_fresh(%{keep_fresh: keep_fresh}) do
    import Helen.Time.Helper, only: [to_binary: 1]

    case keep_fresh[:status] do
      :ready ->
        """
        Reef Keep Fresh is Ready
        """

      :completed ->
        """
        Reef Keep Fresh Completed, elapsed time #{
          to_binary(keep_fresh[:elapsed])
        }.

           Started: #{to_binary(keep_fresh[:started_at])}
          Finished: #{to_binary(keep_fresh[:finished_at])}
        """

      :running ->
        """
        Reef Keep Fresh Running, elapsed time #{to_binary(keep_fresh[:elapsed])}.

                Started: #{to_binary(keep_fresh[:started_at])}

              Executing: #{inspect(keep_fresh[:active_step])}
                Command: #{inspect(keep_fresh[:step][:cmd])}
                Elapsed: #{to_binary(keep_fresh[:step][:elapsed])}
                 Cycles: #{inspect(keep_fresh[:step][:cycles])}
        """
    end
  end
end
