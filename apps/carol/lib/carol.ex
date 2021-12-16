defmodule Carol do
  @moduledoc """
  Carol API
  """

  def call(msg, server) when is_map(msg) and is_atom(server) do
    Carol.Server.call(server, msg)
  end

  def program(server, opts) when is_list(opts) do
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{id: id, params: true} -> %{program: id, cmd: true, params: true}
    end
    |> Carol.call(server)
  end
end
