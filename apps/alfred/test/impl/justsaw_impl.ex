defmodule Alfred.JustSawImpl do
  use Alfred.JustSaw

  def status(_name, _opts), do: :ok
  def execute(_name, _opts), do: :ok
end
