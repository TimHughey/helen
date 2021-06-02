defmodule Sally.MsgInFlight do
  defstruct ident: nil,
            data_rc: :none,
            data: nil,
            release: nil,
            just_saw: {:none, nil},
            metric_rc: {:none, nil},
            faults: []
end
