defmodule Alfred.Command do
  @moduledoc false

  use Alfred.Track, timeout_after: "PT3.3S", metrics_interval: "PT1M", cmd_opts: [notify_when_released: true]

  defstruct refid: nil,
            cmd: "off",
            acked: true,
            orphaned: false,
            rt_latency_us: nil,
            sent_at: nil,
            acked_at: nil,
            dev_alias: nil,
            track: nil

  @tz "America/New_York"

  @unknown "unknown"
  def execute(%Alfred.DevAlias{parts: parts, status: status_cmd}, opts) do
    parts_cmd = parts[:cmd] || @unknown
    exec_cmd = opts[:cmd] || @unknown
    force? = get_in(opts, [:cmd_opts, :force]) || true

    case {parts_cmd, exec_cmd} do
      {cmd, cmd} when force? -> %{rc: :busy, cmd: cmd} |> new(now(), opts)
      {cmd, cmd} -> status_cmd
      {p_cmd, e_cmd} when p_cmd != e_cmd -> %{rc: :busy, cmd: e_cmd} |> new(now(), opts)
    end
  end

  @impl true
  def track_timeout(%Alfred.Track{} = track) do
    Process.send(self(), {__MODULE__, :timeout, track}, [])
  end

  @impl true
  def track_now?(what, _opts) do
    case what do
      %{acked: false} -> true
      _ -> false
    end
  end

  def new(%{cmd: cmd} = parts, at, opts) when is_map(parts) do
    case parts do
      %{rc: :ok} -> [acked: true, acked_at: at]
      %{rc: :busy} -> [acked: false]
      %{rc: :timeout} -> [acked: true, orphaned: true, acked_at: shift_ms(at, 1)]
      %{rc: :expired} -> [acked: true, orphaned: false, acked_at: shift_ms(at, -1000)]
      _ -> []
    end
    |> then(fn fields -> [ref_dt: at, cmd: cmd, refid: make_refid()] ++ fields end)
    |> sent_at()
    |> rt_latency_us()
    |> new(opts)
    |> track([name: Map.get(parts, :name)] ++ opts)
  end

  def new(fields, _opts), do: struct(__MODULE__, fields)

  def local_now, do: Timex.now(@tz)

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
    ref_dt = Keyword.get(fields, :ref_dt, local_now())

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
