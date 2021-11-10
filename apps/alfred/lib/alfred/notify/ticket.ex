defmodule Alfred.Notify.Ticket do
  alias __MODULE__

  alias Alfred.Notify.Entry

  defstruct name: nil, ref: nil, opts: %{interval_ms: nil, missing_ms: nil, ttl_ms: nil}

  @type interval_ms() :: :all | pos_integer()
  @type missing_ms() :: 0 | pos_integer()
  @type ttl_ms() :: 0 | pos_integer()
  @type zero_or_pos_integer() :: 0 | pos_integer()
  @type ticket_opts() ::
          %{interval_ms: interval_ms(), missing_ms: missing_ms(), ttl_ms: ttl_ms()}

  @type t :: %Ticket{name: String.t(), ref: reference(), opts: ticket_opts()}

  def new(%Entry{} = e) do
    opts = %{
      interval_ms: if(e.interval_ms == 0, do: :all, else: e.interval_ms),
      missing_ms: e.missing_ms,
      ttl_ms: e.ttl_ms
    }

    %Ticket{name: e.name, ref: e.ref, opts: opts}
  end
end
