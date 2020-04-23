defmodule Helen.Server do
  @moduledoc """
  Helen Globally Exposed API Server

  Decoupling for external clients that wish to use functionality provided
  by Helen.

  > This module __does not__ provide the actual client code.  Rather, the
  > module provides a GenServer which calls local modules and functions.
  >
  > In short, this GenServer wraps internal Helen functionality.
  """

  @moduledoc since: "0.0.4"

  require Logger
  use GenServer

  #
  ## GenServer Callbacks
  #

  @doc """
    init() callback
  """
  @impl true
  @doc since: "0.0.4"
  def init(%{} = state) do
    {:ok, state}
  end

  @doc """
  Start the Helen Server
  """

  @doc since: "0.0.4"
  def start_link(%{start_workers: true} = args) do
    GenServer.start_link(
      __MODULE__,
      %{initial_args: args},
      name: {:global, :helen_server}
    )
  end

  def start_link(%{} = _args), do: :ignore

  #
  ## handle_call() callbacks
  #

  @impl true
  def handle_call({_a, _b, _c} = ast, _from, %{} = s) do
    try do
      {res, _bindings} = Code.eval_quoted(ast)
      {:reply, res, s}
    rescue
      error -> {:reply, error, s}
    end
  end

  @impl true
  def handle_call(catchall, _from, %{} = s),
    do: {:reply, {:unhandled, catchall}, s}
end
