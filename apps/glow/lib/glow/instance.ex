defmodule Glow.Instance do
  @moduledoc """
  Glow instance assistant

  """

  @doc "Create instance id"
  @doc since: "0.1.0"
  def id(instance) when is_atom(instance) do
    suffix = to_string(instance) |> Macro.camelize()

    ["Glow", suffix] |> Module.concat()
  end
end
