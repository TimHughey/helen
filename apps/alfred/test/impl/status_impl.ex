defmodule Alfred.StatusImpl do
  use Alfred.Status
  use Alfred.JustSaw

  def register(name, opts) do
    name
    |> Alfred.NamesAid.binary_to_parts()
    |> Alfred.Test.DevAlias.new()
    |> Alfred.Name.register(opts)
  end

  @impl true
  # NOTE: we cheat here by not using nature since ALfred.Test.DevAlias.new/1 magically
  # creates the correct DevAlias based on the name parts
  def status_lookup(%{name: name, nature: _nature} = _info, _opts) do
    Alfred.NamesAid.binary_to_parts(name)
    |> Alfred.Test.DevAlias.new()
  end
end
