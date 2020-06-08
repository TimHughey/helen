defmodule Keeper do
  @moduledoc """
    Agent for serverless modules to store their "state"

  """

  use Agent

  def start_link(args) do
    Agent.start_link(fn -> Enum.into(args, %{}) end, name: __MODULE__)
  end

  def get_key(key) when is_atom(key) do
    Agent.get(__MODULE__, fn
      %{} = s -> Map.get(s, key)
      s -> s
    end)
  end

  def merge(key, map) when is_atom(key) and is_map(map) do
    Agent.get_and_update(__MODULE__, fn
      %{} = s ->
        existing = Map.get(s, key, %{})
        updated = Map.merge(existing, map)
        s = Map.put(s, key, update)
        {updated, s}

      s ->
        {%{}, s}
    end)
  end

  def put_key(key, value) when is_atom(key) do
    Agent.update(__MODULE__, fn
      %{} = s -> Map.put(s, key, value)
      s -> s
    end)
  end
end
