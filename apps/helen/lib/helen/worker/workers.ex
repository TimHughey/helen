defmodule Helen.Workers do
  @moduledoc """
  Abstraction to find the module for a Worker.

  A worker is either:
    a. a Reef worker (e.g. FirstMate)
    b. a GenDevice (e.g. Reef.MixTank.Air)
    c. a simple device (e.g. Switch, PulseWidth)
  """

  def all do
    alias Reef.{DisplayTank, MixTank}

    for mod <- [
          MixTank.Air,
          MixTank.Pump,
          MixTank.Rodi,
          MixTank.Temp,
          DisplayTank.Ato,
          DisplayTank.Temp
        ] do
      mod.device_module_map()
    end
  end

  def build_module_cache(nil), do: %{}

  def build_module_cache(workers_map) when is_map(workers_map) do
    for {ident, name} <- workers_map, into: %{} do
      {ident, module(ident, name)}
    end
  end

  def module_cache_complete?(cache) do
    for {_ident, entry} <- cache, reduce: true do
      true -> entry[:found?] || false
      false -> false
    end
  end

  def craft_response(%{find: {ident, name}, module: mod, type: type}) do
    base = %{ident: ident, name: name, module: mod, type: type}

    case mod do
      nil -> put_in(base, [:found?], false)
      x when is_atom(x) -> put_in(base, [:found?], true)
      _ -> put_in(base, [:found?], false)
    end
  end

  def execute(action) do
    action
  end

  def make_action(
        msg_type,
        worker_cache,
        %{worker: worker_ref} = action,
        token
      ) do
    Map.merge(action, %{
      msg_type: msg_type,
      worker: get_in(worker_cache, [worker_ref]),
      reply_to: self(),
      ref: make_ref(),
      token: token
    })
  end

  def module(ident, name) do
    %{find: {ident, name}, module: nil, type: nil}
    |> search(:workers)
    |> search(:reef_workers)
    |> search(:simple_devices)
    |> craft_response()
  end

  #
  # Search Reef Workers (e.g. FirstMate)
  #

  # only one Reef Worker that can be used in a worker config exists
  def search(
        %{find: {:first_mate, :reef_worker}, module: nil} = acc,
        :reef_workers
      ),
      do:
        put_in(acc, [:module], Reef.FirstMate) |> put_in([:type], :reef_worker)

  # already found?  then do nothing
  def search(%{find: _, module: mod} = acc, :reef_workers) when is_atom(mod),
    do: acc

  # no match, pass through the accumulator
  def search(acc, :reef_workers), do: acc

  #
  # Search Simple Devices (e.g. Switch, PulseWidth)
  #

  #
  # Search Simple Devices (e.g. Switch, PulseWidth)
  #
  # nothing found yet, search all simple devices
  def search(%{find: {_ident, name}, module: nil} = acc, :simple_devices) do
    for x <- [PulseWidth, Switch], reduce: acc do
      %{module: nil} = acc ->
        if x.exists?(name) do
          put_in(acc, [:module], x) |> put_in([:type], :simple_device)
        else
          acc
        end

      acc ->
        acc
    end
  end

  # already found?  then do nothing
  def search(acc, :simple_devices), do: acc

  #
  # Search Workers (e.g. GenDevice based modules)
  #
  # not found?  then search through all workers for a matching name
  def search(%{find: {_ident, name}, module: nil} = acc, :workers) do
    for %{name: x, module: mod} when x == name <- all(), reduce: acc do
      acc -> put_in(acc, [:module], mod) |> put_in([:type], :gen_device)
    end
  end

  #
  # Search Workers (e.g. GenDevice based modules)
  #
  # already found?  then do nothing
  def search(acc, :workers), do: acc
end
