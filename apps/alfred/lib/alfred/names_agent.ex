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

  def just_saw([%{} | _] = raw_list, mod) when is_atom(mod) do
    Agent.update(This, State, :update_known, [make_known_names(raw_list, mod)])
  end

  def just_saw([%{} | _] = raw_list, %DateTime{} = seen_at, mod) when is_atom(mod) do
    Agent.update(This, State, :update_known, [make_known_names(raw_list, mod, seen_at)])
  end

  def pid do
    Agent.get_and_update(This, State, :store_and_return_pid, [])
  end

  defp make_known_names(list, mod, seen_at \\ DateTime.utc_now()) do
    for %{name: name} = map when is_binary(name) <- list do
      case map do
        # schema has pio, it's mutable
        %_{pio: _, ttl_ms: ttl_ms} ->
          %KnownName{
            name: name,
            mod: mod,
            # if :pio exists this is a mutable device
            mutable: true,
            seen_at: seen_at,
            ttl_ms: ttl_ms
          }

        # schema does not have pio, immutable
        %_{ttl_ms: ttl_ms} ->
          %KnownName{
            name: name,
            mod: mod,
            # if :pio exists this is a mutable device
            mutable: false,
            seen_at: seen_at,
            ttl_ms: ttl_ms
          }

        # plain map, use defaults for missing keys
        %{name: name} = x ->
          # if :pio exists this is a mutable device
          mutable = x[:mutable] || (x[:pio] && true)

          %KnownName{
            name: name,
            mod: mod,
            mutable: mutable,
            seen_at: x[:seen_at] || DateTime.utc_now(),
            ttl_ms: x[:ttl_ms] || 30_000
          }
      end
    end
  end
end
