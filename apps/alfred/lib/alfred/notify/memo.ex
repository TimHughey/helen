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

  @type new_opts() :: [seen_at: DateTime.t(), missing?: boolean()]
  @spec new(Entry.t(), new_opts()) :: Memo.t()
  def new(%Entry{} = e, opts) do
    %Memo{
      name: e.name,
      pid: e.pid,
      ref: e.ref,
      seen_at: opts[:seen_at],
      missing?: opts[:missing?]
    }
  end
end
