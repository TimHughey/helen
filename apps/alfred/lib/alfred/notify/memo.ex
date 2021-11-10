defmodule Alfred.Notify.Memo do
  alias __MODULE__
  alias Alfred.Notify.Entry

  defstruct name: "unknown", ref: nil, pid: nil, seen_at: nil, missing?: true

  @type t :: %Memo{
          name: String.t(),
          ref: reference(),
          pid: pid(),
          seen_at: DateTime.t(),
          missing?: boolean()
        }

  def new(%Entry{} = e, opts) do
    %Memo{
      name: opts[:name],
      pid: e.pid,
      ref: e.ref,
      seen_at: opts[:seen_at],
      missing?: opts[:missing?]
    }
  end
end
