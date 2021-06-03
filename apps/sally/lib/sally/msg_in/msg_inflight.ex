defmodule Sally.MsgInFlight do
  alias __MODULE__

  defstruct ident: nil,
            applied_data: :none,
            release: nil,
            just_saw: {:none, nil},
            metric_rc: {:none, nil},
            metrics: [],
            faults: []

  def just_saw(%MsgInFlight{} = mif, seen_list) do
    case Alfred.just_saw(seen_list) do
      {:ok, res} -> %MsgInFlight{mif | just_saw: res}
      error -> %MsgInFlight{mif | faults: [just_saw: error] ++ mif.faults}
    end
  end
end
