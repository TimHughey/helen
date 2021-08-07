defmodule Eva.Ledger do
  require Logger

  alias __MODULE__

  defstruct completed_at: :none,
            accepted_at: :none,
            executed_at: :none,
            released_at: :none,
            expired_at: :none,
            notified_at: :none

  @type t :: %Ledger{
          completed_at: :none | DateTime.t(),
          accepted_at: :none | DateTime.t(),
          executed_at: :none | DateTime.t(),
          released_at: :none | DatwTime.t(),
          expired_at: :none | DateTime.t(),
          notified_at: :none | DateTime.t()
        }

  def new do
    %Ledger{} |> accepted()
  end

  def new(%Ledger{} = l) do
    %Ledger{accepted_at: l.accepted_at}
  end

  def accepted(%Ledger{} = l), do: %Ledger{l | accepted_at: DateTime.utc_now()}
  def completed(%Ledger{} = l), do: %Ledger{l | completed_at: DateTime.utc_now()}
  def executed(%Ledger{} = l), do: %Ledger{l | executed_at: DateTime.utc_now()}
  def expired(%Ledger{} = l), do: %Ledger{l | expired_at: DateTime.utc_now()}
  def in_progress?(%Ledger{} = l), do: l.completed_at == :none
  def notified(%Ledger{} = l), do: %Ledger{l | notified_at: DateTime.utc_now()}
  def released(%Ledger{} = l), do: %Ledger{l | released_at: DateTime.utc_now()}
end
