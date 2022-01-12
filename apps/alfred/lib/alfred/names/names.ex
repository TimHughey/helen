defmodule Alfred.Names do
  @moduledoc """
  Alfred Name Registry

  """

  @registry Alfred.Name.Registry

  @doc since: "0.3.0"
  def registered do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) |> Enum.sort()
  end
end
