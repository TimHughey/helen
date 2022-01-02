defmodule Sally.Config.Agent do
  @moduledoc """
  Sally Runtime configuration `Agent`
  """

  use Agent

  def start_link(args) do
    app_default = Application.get_application(__MODULE__)
    {app, rest} = Keyword.pop(args, :app, app_default)
    {name, merge_config} = Keyword.pop(rest, :name, __MODULE__)

    config = Application.get_all_env(app)
    final_config = Keyword.merge(config, merge_config) |> Enum.into(%{})

    initial_value = %{config: final_config, runtime: %{dirs: %{}}}

    Agent.start_link(fn -> initial_value end, name: name)
  end

  def config_get({_mod, _key} = what), do: category_get(:config, what)

  def runtime_get({_mod, _key} = what), do: category_get(:runtime, what)

  def runtime_put(:none, _), do: :none

  def runtime_put(put_this, {mod, key}) do
    tap(put_this, fn val ->
      Agent.update(__MODULE__, fn %{runtime: runtime} = state ->
        case state do
          %{runtime: %{^mod => kw_list}} -> Keyword.put(kw_list, key, val)
          %{runtime: _} -> [{key, val}]
        end
        |> then(fn mod_kw_list -> Map.put(runtime, mod, mod_kw_list) end)
        |> then(fn new_runtime -> Map.put(state, :runtime, new_runtime) end)
      end)
    end)
  end

  def category_get(category, {mod, key}) do
    Agent.get(__MODULE__, fn state ->
      case state do
        %{^category => %{^mod => [_ | _] = kw_list}} -> Keyword.get(kw_list, key, [])
        _ -> :none
      end
    end)
  end
end
