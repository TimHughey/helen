defmodule Sally.Host.ChangeControl do
  defstruct raw_changes: %{}, required: [], replace: []

  @type raw_change_map() :: %{atom() => String.t() | DateTime.t()}

  @type t :: %__MODULE__{
          raw_changes: raw_change_map(),
          required: nonempty_list(),
          replace: nonempty_list()
        }
end
