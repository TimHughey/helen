defmodule Alfred.NotifyAid do
  @moduledoc """
    Add an `Alfred.Memo` to the test context
  """

  @doc """
    Adds `Alfred.Notify.Memo`, `{Alfred, %Memo{}}` and `memo_before_dt` to test context

    When test context contains `%{memo_add: opts}` a map is returned
    for merge into the test context.
    ```
    %{memo: %Memo{}, memo_before_dt: %DateTime{}, notify_msg: {Alfred, memo}}
    ```

    Automatically finds an `Alfred.Notify.Ticket` or creates one using
    keys found in the test context. The `ticket` is then used to create
    the `memo` and `notify_msg`.

    ```
    # retreives ticket from state
    %{memo_add: [], state: %{ticket: ticket}} |> memo_add()

    # creates a ticket using opts and equipment name
    %{memo_add: opts, equipment: name} |> memo_add()

    # creates a ticket and augments memo via opts
    %{memo_add: [missing?: true], state: %{ticket: ticket}} |> memo_add()

    # creates a generic ticket from ticket opts
    %{memo_add: [interval_ms: 10_000]} |> memo_add()

    > `memo_before_dt` is set to `DateTime.utc_now/0` and is often used to
    > compare `last_notify_at`.
  """
  @doc since: "0.2.6"
  def memo_add(%{memo_add: opts} = ctx) when is_list(opts) do
    # Memo tests generally compare the Memo seen_at
    # so include something to compare to in the context
    now_dt = DateTime.utc_now()

    # find the source Ticket
    case ctx do
      # use the ticket from a state in the context
      %{state: %{ticket: ticket}} -> ticket
      # create a ticket if equipment is available
      %{equipment: x} -> make_ticket([name: x] ++ opts)
      _ -> make_ticket(opts)
    end
    |> make_memo_from_ticket(opts)
    |> final_map(now_dt)
  end

  def memo_add(_), do: :ok

  defp final_map(memo, before_dt) do
    %{memo: memo, memo_before_dt: before_dt, notify_msg: {Alfred, memo}}
  end

  defp make_memo_from_ticket({:ok, %Alfred.Ticket{} = ticket}, opts) do
    make_memo_from_ticket(ticket, opts)
  end

  defp make_memo_from_ticket(%Alfred.Ticket{} = ticket, opts) when is_list(opts) do
    {seen_at, opts_rest} = Keyword.pop(opts, :seen_at, DateTime.utc_now())
    {missing?, _} = Keyword.pop(opts_rest, :missing?, false)

    Map.take(ticket, [:name, :ref])
    |> Map.merge(%{pid: self(), at: %{seen: seen_at}, missing?: missing?})
    |> Alfred.Memo.new([])
  end

  @ticket_defaults [interval_ms: 0, missing_ms: 60_000, send_missing_msg: false]
  defp make_ticket(args) do
    args = Keyword.merge(@ticket_defaults, args)

    %{
      name: Keyword.get(args, :name, "missing name"),
      ref: Keyword.get(args, :ref, make_ref()),
      opts: %{
        ms: %{interval: args[:interval_ms], missing: args[:missing_ms]},
        send_missing_msg: args[:send_missing_msg]
      }
    }
    |> Alfred.Ticket.new()
  end
end
