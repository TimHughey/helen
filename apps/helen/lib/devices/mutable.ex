defmodule MutableDevices do
  use Timex

  # (1 of 2) the device name exists in the device cache
  def exists?(name, %{device_cache: cache}) when is_map_key(cache, name) do
    case get_in(cache, [name]) do
      {:found, _mod, _at} -> true
      {:not_found, _mod, _at} -> false
      x when is_nil(x) -> false
    end
  end

  # (2 of 2) the map passed did not contain a device cache
  def exists?(_name, _), do: false

  # locate a device and store it's corresponding module in the device cache
  # the map enclosing the cache is always returned (suitable for passing a GenServer state)
  def locate(s, name, opts \\ [])

  # (1 of 3) already located the device, return the map enclosing the cache
  def locate(%{device_cache: cache} = s, name, opts)
      when is_map_key(cache, name) and is_list(opts) do
    force = opts[:force] || false

    if force do
      opts = Keyword.delete(opts, :force)
      # when force is selected, delete the existing entry and call locate/2
      update_in(s, [:device_cache], fn cache -> Map.delete(cache, name) end)
      |> locate(name, opts)
    else
      # device already located, nothing to do
      s
    end
  end

  @not_found {:not_found, nil, nil}

  # (2 of 3) device cache exists and there isn't an entry for the named device
  def locate(%{device_cache: cache} = s, name, opts)
      when is_map(cache) and is_list(opts) do
    update_in(s, [:device_cache, name], fn _x -> search(name, opts, s) end)
  end

  # (3 of 3) the map passed does not contain a cache, add one and call locate/2 again
  def locate(s, name, opts)
      when is_map(s) and is_binary(name) and is_list(opts) do
    put_in(s, [:device_cache], %{}) |> locate(name, opts)
  end

  # (1 of 2) confirm the module exports exists?/1
  defp call_mod_exists(mod, name, s) do
    if function_exported?(mod, :exists?, 1) do
      call_mod_exists(mod, name, :has_function, s)
    else
      @not_found
    end
  end

  # (2 of 2) function is available, call exists?/1
  defp call_mod_exists(mod, name, :has_function, s) do
    import Helen.Time.Helper, only: [local_now: 1]

    if mod.exists?(name) do
      {:found, mod, local_now(s)}
    else
      @not_found
    end
  end

  defp search(name, opts, s) do
    for mod when is_atom(mod) <- search_mods(opts), reduce: @not_found do
      @not_found -> call_mod_exists(mod, name, s)
      found -> found
    end
  end

  @default_mods [PulseWidth, Switch]
  defp search_mods(opts) do
    case opts[:mods] do
      x when is_list(x) -> x
      _ -> @default_mods
    end
  end
end
