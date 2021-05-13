defmodule Alfred.NamesAgent do
  use Agent, shutdown: 1000

  alias __MODULE__, as: This
  alias Alfred.KnownName
  alias Alfred.NamesAgentState, as: State

  def start_link(_initial_value) do
    Agent.start_link(fn -> %State{} end, name: This)
  end

  def exists?(name) when is_binary(name) do
    case get(name) do
      %KnownName{} -> true
      _ -> false
    end
  end

  def get(name) when is_binary(name) do
    Agent.get_and_update(This, State, :get_name_entry, [name])
  end

  def known do
    Agent.get(This, State, :all_known, [])
  end

  # (1 of 3) raw list of maps representing seen names
  def just_saw([%{} | _] = raw_list) do
    Agent.get_and_update(This, State, :just_saw, [make_known_names(raw_list)])
  end

  # (2 of 3) empty lists are ok
  def just_saw([]), do: {:ok, []}

  # (3 of 3) previous function in pipeline error
  def just_saw(previous_rc), do: previous_rc

  def pid do
    Agent.get_and_update(This, State, :store_and_return_pid, [])
  end

  # (1 od 2) list of structs
  defp make_known_names([%{__struct__: _} | _] = seen_list) do
    # when the struct has cmds it is mutable.  conversely, when it has datapoints it is not
    mutable? = fn
      %_{cmds: _} -> true
      %_{datapoints: _} -> false
    end

    # the callback module is the first level of the struct
    callback_mod = fn %{__struct__: x} -> Module.split(x) |> Enum.take(1) |> Module.concat() end

    for seen <- seen_list do
      %KnownName{
        name: seen.name,
        callback_mod: callback_mod.(seen),
        # if :pio exists this is a mutable device
        mutable: mutable?.(seen),
        seen_at: seen.updated_at,
        ttl_ms: seen.ttl_ms
      }
    end
  end

  # (2 of 2) list of plain seen maps, must have name and callback mod
  # will default to immutable if not specified
  defp make_known_names(seen_list) when is_list(seen_list) do
    for %{name: name, callback_mod: mod} = seen <- seen_list do
      %KnownName{
        name: name,
        callback_mod: mod,
        mutable: seen[:mutable] || false,
        seen_at: seen[:seen_at] || DateTime.utc_now(),
        ttl_ms: seen[:ttl_ms] || 30_000
      }
    end
  end
end
