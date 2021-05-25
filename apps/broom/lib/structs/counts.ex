defmodule Broom.Counts do
  alias __MODULE__

  alias Broom.TrackerEntry, as: Entry

  defstruct tracked: 0, released: 0, orphaned: 0, errors: 0

  @type t :: %__MODULE__{
          tracked: non_neg_integer(),
          released: non_neg_integer(),
          orphaned: non_neg_integer(),
          errors: non_neg_integer()
        }

  def increment(key, %Counts{} = c) when is_map_key(c, key) do
    new_count = Map.get(c, key) + 1
    Map.put(c, key, new_count)
  end

  def released_entry(%Entry{} = te, %Counts{} = c) do
    case te do
      %Entry{orphaned: true} -> increment(:orphaned, c)
      %Entry{acked: true} -> increment(:released, c)
      _ -> increment(:errors, c)
    end
  end

  def reset(%Counts{} = c, keys) when is_list(keys) do
    for key <- keys, reduce: c do
      %Counts{} = c -> reset_one(c, key)
    end
  end

  # (1 of 2)
  defp reset_one(%Counts{} = c, key) when is_map_key(c, key) do
    Map.put(c, key, 0)
  end

  # (2 of 2)
  defp reset_one(%Counts{} = c, _key), do: c
end
