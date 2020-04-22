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

  @doc """
    Handling of exposed API calls
  """
  @doc since: "0.0.4"
  @impl true
  def handle_call(
        %{module: :dutycycle, function: function, args: args},
        _from,
        %{} = s
      )
      when is_atom(function) and is_list(args) do
    res =
      try do
        apply(Dutycycle.Server, function, args)
      rescue
        error -> error
      end

    {:reply, res, s}
  end

  @impl true
  def handle_call(
        %{module: :pwm, function: function, args: args},
        _from,
        %{} = s
      )
      when is_atom(function) and is_list(args) do
    res =
      try do
        apply(PulseWidth, function, args)
      rescue
        error -> error
      end

    {:reply, res, s}
  end

  @impl true
  def handle_call(
        %{module: :remote, function: function, args: args},
        _from,
        %{} = s
      )
      when is_atom(function) and is_list(args) do
    res =
      try do
        apply(Remote, function, args)
      rescue
        error -> error
      end

    {:reply, res, s}
  end

  def handle_call(
        %{module: :sensor, function: function, args: args},
        _from,
        %{} = s
      )
      when is_atom(function) and is_list(args) do
    res =
      try do
        apply(Sensor, function, args)
      rescue
        error -> error
      end

    {:reply, res, s}
  end

  def handle_call(
        %{module: :switch, function: function, args: args},
        _from,
        %{} = s
      )
      when is_atom(function) and is_list(args) do
    res =
      try do
        apply(Switch, function, args)
      rescue
        error -> error
      end

    {:reply, res, s}
  end

  @impl true
  def handle_call(
        %{module: :thermostat, function: function, args: args},
        _from,
        %{} = s
      )
      when is_atom(function) and is_list(args) do
    res =
      try do
        apply(Thermostat.Server, function, args)
      rescue
        error -> error
      end

    {:reply, res, s}
  end

  @impl true
  def handle_call(catchall, _from, %{} = s),
    do: {:reply, {:unhandled, catchall}, s}
end
