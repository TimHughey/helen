defmodule Helen.Workers.ModCache do
  @moduledoc false

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

  def craft_response(%{find: {ident, name}, module: mod, type: type}) do
    base = %{ident: ident, name: name, module: mod, type: type}

    case mod do
      nil -> put_in(base, [:found?], false)
      x when is_atom(x) -> put_in(base, [:found?], true)
      _ -> put_in(base, [:found?], false)
    end
  end

  @doc false
  def module(ident, name) do
    %{find: {ident, name}, module: nil, type: nil}
    |> search(:workers)
    |> search(:reef_workers)
    |> search(:roost_workers)
    |> search(:simple_devices)
    |> craft_response()
  end

  #
  # Search Reef Workers (e.g. FirstMate)
  #

  # only one Reef Worker that can be used in a worker config exists
  defp search(
         %{find: {:first_mate, "reef worker"}, module: nil} = acc,
         :reef_workers
       ),
       do:
         put_in(acc, [:module], Reef.FirstMate.Server)
         |> put_in([:type], :reef_worker)

  # only one Roost Worker that can be used in a worker config exists
  defp search(
         %{find: {:lightdesk, "roost worker"}, module: nil} = acc,
         :roost_workers
       ),
       do:
         put_in(acc, [:module], LightDesk)
         |> put_in([:type], :roost_worker)

  # already found?  then do nothing
  defp search(%{find: _, module: mod} = acc, type)
       when is_atom(mod) and type in [:reef_workers, :roost_workers],
       do: acc

  # no match, pass through the accumulator
  defp search(acc, :reef_workers), do: acc

  #
  # Search Simple Devices (e.g. Switch, PulseWidth)
  #

  #
  # Search Simple Devices (e.g. Switch, PulseWidth)
  #
  # nothing found yet, search all simple devices
  defp search(%{find: {_ident, name}, module: nil} = acc, :simple_devices) do
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
  defp search(acc, :simple_devices), do: acc

  #
  # Search Workers (e.g. GenDevice based modules)
  #
  # not found?  then search through all workers for a matching name
  defp search(%{find: {_ident, name}, module: nil} = acc, :workers) do
    for %{name: x, module: mod, type: type} when x == name <- all(),
        reduce: acc do
      acc -> put_in(acc, [:module], mod) |> put_in([:type], type)
    end
  end

  #
  # Search Workers (e.g. GenDevice based modules)
  #
  # already found?  then do nothing
  defp search(acc, :workers), do: acc
end
