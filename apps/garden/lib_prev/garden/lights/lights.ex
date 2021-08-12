defmodule Lights do
  @moduledoc """
  Control and operate automated Lights
  """

  alias Lights.Server

  import Server, only: [call: 2]

  @doc """
    Is the server alive?

    ```elixir

        iex> Lights.Server.alive?()
        true

        iex> Lights.Server.alive?(name: Server.Name)
        false
    ```

  """
  defdelegate alive?(args \\ []), to: Server

  def config(args \\ []) do
    case call(:cfg, args) do
      :no_server -> :no_server
      x -> x
    end
  end

  def load_config(args \\ []), do: call(:load_cfg, args)

  def timeouts(args \\ []) do
    call(:timeouts, args)
  end
end
