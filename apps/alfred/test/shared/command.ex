defmodule Alfred.Test.Command do
  @moduledoc false

  use Alfred.Broom, timeout_after: "PT3.3S", metrics_interval: "PT1M", cmd_opts: [notify_when_released: true]

  defstruct refid: nil,
            cmd: "off",
            acked: true,
            orphaned: false,
            rt_latency_us: nil,
            sent_at: nil,
            acked_at: nil,
            dev_alias: nil

  @tz "America/New_York"

  def ack_now(refid, ack_at, disposition) do
    {__MODULE__, refid, ack_at, disposition}
    |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.puts() end)

    :ok
  end

  def add(%Alfred.Test.DevAlias{name: _name}, opts) do
    {at, opts_rest} = Keyword.pop(opts, :ref_dt, now())
    {cmd, opts_rest} = Keyword.pop(opts_rest, :cmd)
    {cmd_opts, _opts_rest} = Keyword.pop(opts_rest, :cmd_opts)

    {ack, _cmd_opts_rest} = Keyword.pop(cmd_opts, :ack)

    parts = %{rc: (ack == :immediate && :ok) || :pending, cmd: cmd}

    inserted_cmd = new(parts, at)

    case parts do
      %{rc: :ok} -> {:ok, inserted_cmd}
      %{rc: :pending} -> {:pending, inserted_cmd}
      _ -> {:error, inserted_cmd}
    end
  end

  def broom_timeout(%Alfred.Broom{} = broom) do
    broom |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.puts() end)
  end

  def new(%{cmd: cmd} = parts, at) when is_map(parts) do
    case parts do
      %{rc: :ok} -> [acked: true, acked_at: at]
      %{rc: :pending} -> [acked: false]
      %{rc: :orphaned} -> [acked: true, orphaned: true, acked_at: shift_ms(at, 1)]
      %{rc: :expired} -> [acked: true, orphaned: false, acked_at: shift_ms(at, -1000)]
      _ -> []
    end
    |> then(fn fields -> [{:ref_dt, at} | [{:cmd, cmd} | [{:refid, make_refid()} | fields]]] end)
    |> sent_at()
    |> rt_latency_us()
    |> new()
  end

  def new(fields), do: struct(__MODULE__, fields)

  def now, do: Timex.now(@tz)

  def rt_latency_us(fields) do
    acked = Keyword.get(fields, :acked, false)
    acked_at = Keyword.get(fields, :acked_at, :none)
    sent_at = Keyword.get(fields, :sent_at, shift_ms(acked_at, -20))

    case {acked, acked_at, sent_at} do
      {false, _, _} -> fields
      {true, %DateTime{}, %DateTime{}} -> [{:rt_latency_us, diff_ms(acked_at, sent_at)} | fields]
      _ -> [{:rt_latency_us, 0} | fields]
    end
  end

  def sent_at(fields) do
    acked = Keyword.get(fields, :acked, false)
    acked_at = Keyword.get(fields, :acked_at, :none)
    ref_dt = Keyword.get(fields, :ref_dt, now())

    case {acked, acked_at} do
      {true, %DateTime{}} -> shift_ms(acked_at, -20)
      {_, _} -> shift_ms(ref_dt, -20)
    end
    |> then(fn sent_at -> [{:sent_at, sent_at} | fields] end)
  end

  # DateTime calculations
  def diff_ms(lhs, rhs), do: Timex.diff(lhs, rhs, :milliseconds)
  def shift_ms(dt, ms), do: Timex.shift(dt, milliseconds: ms)
end
