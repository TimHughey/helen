defmodule Alfred do
  @moduledoc """
  Alfred - Master of devices
  """

  alias Alfred.NamesAgent

  def just_saw(%{states_rc: states_rc, device: {:ok, device}} = in_msg, mod) do
    {_rc, results} = states_rc
    seen = for %{schema: x} <- results, do: x

    %_{last_seen_at: seen_at} = device

    NamesAgent.just_saw(seen, seen_at, mod)

    in_msg
  end

  defdelegate known, to: NamesAgent
end
