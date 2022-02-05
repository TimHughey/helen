defmodule Alfred.Client do
  use Alfred, name: [backend: :module], execute: []

  @impl true
  def execute_cmd(_, _), do: nil

  @impl true
  def status_lookup(_, _), do: nil
end
