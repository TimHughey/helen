defmodule Alfred.Test.Support do
  use Should

  defmacro __using__(_opts) do
    quote do
      alias Alfred.Test.Support
      import Support
    end
  end

  defmacro should_be_known_name(res) do
    quote location: :keep, bind_quoted: [res: res] do
      should_be_struct(res, Alfred.KnownName)
      should_be_refuted(res.name, "unknown")
      should_be_equal(res.missing?, false)
    end
  end

  def unique(what) when is_atom(what) do
    unique = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case what do
      :name -> "name #{unique}"
    end
  end
end
