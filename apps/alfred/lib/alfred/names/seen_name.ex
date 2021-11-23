defmodule Alfred.SeenName do
  alias __MODULE__

  defstruct name: nil, seen_at: nil, ttl_ms: nil, valid?: true

  @type t :: %SeenName{
          name: String.t(),
          seen_at: DateTime.t(),
          ttl_ms: pos_integer(),
          valid?: boolean()
        }

  def from_map(%{name: n, ttl_ms: ms, updated_at: at}) do
    %SeenName{name: n, ttl_ms: ms, seen_at: at}
  end

  def from_schema(%{name: _, ttl_ms: _, updated_at: _x} = x) do
    struct(SeenName, name: x.name, ttl_ms: x.ttl_ms, seen_at: x.updated_at)
  end

  def validate([]), do: []

  def validate([%SeenName{} | _] = list) do
    for %SeenName{} = seen <- list, reduce: [] do
      acc ->
        case validate(seen) do
          %SeenName{valid?: true} = x -> [x] ++ acc
          _ -> acc
        end
    end
    |> Enum.reverse()
  end

  def validate(%SeenName{name: name, seen_at: %DateTime{}} = js) when is_binary(name) do
    case js do
      %SeenName{ttl_ms: x} when is_integer(x) and x > 0 -> valid(js)
      _ -> invalid(js)
    end
  end

  def validate(%SeenName{} = js), do: invalid(js)

  defp invalid(%SeenName{} = js), do: %SeenName{js | valid?: false}
  defp valid(%SeenName{} = js), do: %SeenName{js | valid?: true}
end
