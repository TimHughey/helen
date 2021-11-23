defmodule Alfred.Names.State do
  alias __MODULE__
  alias Alfred.KnownName

  defstruct known: %{}

  @type name :: String.t()
  @type t :: %__MODULE__{known: %{optional(name()) => KnownName.t()}}

  def all_known(%State{} = s) do
    for {_name, entry} <- s.known, do: entry
  end

  # (1 of 3) handle empty list
  def add_or_update_known([], %State{} = s), do: s

  # (2 of 4) add a single valid KnownName
  def add_or_update_known(%KnownName{valid?: true} = kn, %State{} = s) do
    %State{s | known: put_in(s.known, [kn.name], kn)}
  end

  # (3 of 4) don't add invalid KnownNames
  def add_or_update_known(%KnownName{valid?: false}, %State{} = s), do: s

  # (4 of 4) handle list of KnownNames
  def add_or_update_known([%KnownName{} | _] = names, %State{} = s) do
    for %KnownName{} = kn <- names, reduce: s do
      new_state -> add_or_update_known(kn, new_state)
    end
  end

  def delete_known(name, %State{} = s), do: %State{s | known: Map.delete(s.known, name)}

  def lookup(name, %State{} = s) do
    case get_in(s.known, [name]) do
      x when is_nil(x) -> KnownName.unknown(name)
      %KnownName{} = kn -> kn |> KnownName.detect_missing()
    end
  end

  def new, do: %State{}
end
