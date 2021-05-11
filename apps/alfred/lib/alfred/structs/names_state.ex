defmodule Alfred.NamesAgentState do
  alias __MODULE__, as: State
  alias Alfred.KnownName, as: Name

  defstruct known_map: %{}, pid: nil

  def get_name_entry(%State{} = s, name) do
    s = prune_expired(s)

    found =
      for {key, entry} when key == name <- s.known_map(), reduce: nil do
        _ -> entry
      end

    {found, s}
  end

  def store_and_return_pid(%State{} = s) do
    s = %State{s | pid: self()}

    {s.pid, s}
  end

  def prune_expired(%State{} = s) do
    %State{
      s
      | known_map:
          for {key, %Name{} = entry} <- s.known_map, reduce: s.known_map do
            known_map ->
              # if expired remove the %Name{} from the known map
              if EasyTime.seen_at_expired?(entry) do
                Map.delete(known_map, key)
              else
                known_map
              end
          end
    }
  end

  def update_known(%State{} = s, list) do
    %State{
      s
      | # replace or add each %KnownName{} to the known map
        known_map:
          for entry <- list, reduce: s.known_map do
            known_map -> put_in(known_map, [entry.name], entry)
          end
    }
    |> prune_expired()
  end
end
