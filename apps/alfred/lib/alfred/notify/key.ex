defmodule Alfred.Notify.Registration.Key do
  alias __MODULE__

  defstruct name: nil, notify_pid: nil, ref: nil

  @type t :: %Key{
          name: String.t(),
          notify_pid: pid(),
          ref: reference()
        }
end
