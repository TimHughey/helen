defmodule Sally.Config do
  @moduledoc """
  Sally Runtime configuration API
  """

  def dir_get({mod, dir} = what) when is_atom(dir) or is_binary(dir) do
    runtime_dirs = Sally.Config.Agent.runtime_get(what)

    case runtime_dirs do
      %{^mod => %{^dir => val}} -> val
      _ -> Sally.Config.Directory.discover(what) |> Sally.Config.Agent.runtime_put(what)
    end
  end

  def dir_get(_), do: :none

  # def mod_get(mod) do
  #   Sally.Config.Agent.config_get()
  # end
end
