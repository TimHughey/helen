defmodule Alfred.Test.Support do
  def unique(what) when is_atom(what) do
    unique = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case what do
      :name -> "name #{unique}"
    end
  end
end
