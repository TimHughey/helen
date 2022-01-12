defmodule Alfred.Test.Command do
  @moduledoc false

  defstruct refid: nil,
            cmd: "off",
            acked: true,
            orphaned: false,
            rt_latency_us: nil,
            sent_at: nil,
            acked_at: nil

  @tz "America/New_York"

  def new(%{cmd: cmd} = parts, at) when is_map(parts) do
    case parts do
      %{rc: :ok} -> [acked: true, acked_at: at]
      %{rc: :pending} -> [acked: false]
      %{rc: :orphaned} -> [acked: true, orphaned: true, acked_at: shift_ms(at, 1)]
      %{rc: :expired} -> [acked: true, orphaned: false, acked_at: shift_ms(at, -1000)]
      _ -> []
    end
    |> then(fn fields -> [{:ref_dt, at} | [{:cmd, cmd} | [{:refid, refid()} | fields]]] end)
    |> sent_at()
    |> rt_latency_us()
    |> new()
  end

  def new(fields), do: struct(__MODULE__, fields)

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp now, do: Timex.now(@tz)
  defp refid, do: Ecto.UUID.generate() |> String.split("-") |> List.first()

  defp rt_latency_us(fields) do
    acked = Keyword.get(fields, :acked, false)
    acked_at = Keyword.get(fields, :acked_at, :none)
    sent_at = Keyword.get(fields, :sent_at, shift_ms(acked_at, -20))

    case {acked, acked_at, sent_at} do
      {false, _, _} -> fields
      {true, %DateTime{}, %DateTime{}} -> [{:rt_latency_us, diff_ms(acked_at, sent_at)} | fields]
      _ -> [{:rt_latency_us, 0} | fields]
    end
  end

  defp sent_at(fields) do
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
  defp diff_ms(lhs, rhs), do: Timex.diff(lhs, rhs, :milliseconds)

  defp shift_ms(dt, ms), do: Timex.shift(dt, milliseconds: ms)
end
