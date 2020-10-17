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
end
