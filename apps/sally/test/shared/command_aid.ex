defmodule Sally.CommandAid do
  @moduledoc """
  Supporting functionality for creating Sally.Command for testing
  """

  def cmd_from_opts(pin, pin_opts) do
    Enum.reduce(pin_opts, random_cmd(), fn {pin_num, cmd}, acc ->
      if(pin == pin_num, do: cmd, else: acc)
    end)
  end

  def cmd_from(what) do
    case what do
      %Sally.DevAlias{} = dev_alias -> Sally.Command.latest_cmd(dev_alias) |> cmd_from()
      %Sally.Command{acked: false} -> random_cmd()
      %Sally.Command{acked: true, orphaned: true} -> random_cmd()
      %Sally.Command{acked: true, cmd: cmd} -> cmd
      :none -> "off"
      _ -> "UNKNOWN"
    end
  end

  def dispatch(%{category: "cmdack"}, opts_map) do
    unless is_map_key(opts_map, :cmd_latest), do: raise(":cmd_latest is missing")

    cmd = find_busy(opts_map.cmd_latest)

    if not match?(%{acked: false}, cmd), do: raise("cmd should be busy")

    filter_extra = [cmd.refid]
    data = %{}

    [filter_extra: filter_extra, data: data]
  end

  def dispatch(%{category: "status"}, opts_map) do
    unless is_map_key(opts_map, :device), do: raise(":device missing")

    %{device: %{pios: pin_count, ident: device_ident}, opts: opts} = opts_map

    status = opts[:status] || "ok"
    cmd_args = opts[:cmds] || []
    pins = cmd_args[:pins] || []
    data = %{pins: make_pins(pin_count, pins)}

    [filter_extra: [device_ident, status], data: data]
  end

  def echo_opts(cmd_args) do
    Map.take(cmd_args, [:echo]) |> Enum.into([])
  end

  def find_busy(cmds) do
    case cmds do
      [_ | _] -> Enum.random(cmds)
      %{acked: false, acked_at: nil} = cmd -> cmd
      _ -> nil
    end
  end

  def historical(%Sally.DevAlias{} = dev_alias, opts_map) do
    history = get_in(opts_map, [:cmds, :history]) || 1

    Enum.map(1..history, fn num ->
      Process.sleep(10)

      type = if num == history, do: :last, else: :history

      cmd_opts = historical_cmd_opts(type, opts_map) ++ echo_opts(opts_map)
      cmd_args = [cmd: random_cmd(), cmd_opts: cmd_opts]

      case Sally.DevAlias.execute_cmd(dev_alias, cmd_args) do
        {:ok, %{acked: true, acked_at: %DateTime{}, orphaned: false}} = rc -> rc
        # NOTE: verify only the latest command is busy (aka busy)
        {:busy, %{acked: false}} = rc when num == history -> rc
        error_rc -> raise("execute error: #{inspect(error_rc, pretty: true)}")
      end
      |> track(cmd_args)
      |> send_payload(cmd_args)
    end)
  end

  @immediate [ack: :immediate]
  def historical_cmd_opts(:last, %{_cmds_: cmd_args}) do
    latest_args = Map.take(cmd_args, [:latest])

    case latest_args do
      %{latest: :busy} -> []
      %{latest: :orphan} -> [timeout_ms: 0]
      %{} = latest_args when map_size(latest_args) == 0 -> @immediate
      bad_args -> raise("bad args; #{inspect(bad_args)}")
    end
  end

  def historical_cmd_opts(_type, _), do: @immediate

  def latest(%{dev_alias: dev_alias}) do
    case dev_alias do
      %{} -> Sally.Command.saved(dev_alias)
      [_ | _] = many -> Enum.map(many, fn dev_alias -> Sally.Command.saved(dev_alias) end)
    end
  end

  @make_pin_opts [:from_status, :random]
  def make_pin(source, pin_num, [kind]) when kind in @make_pin_opts do
    case {source, kind} do
      {%{name: _} = dev_alias, :from_status} -> [pin_num, cmd_from(dev_alias)]
      {_any, :random} -> [pin_num, random_cmd()]
      {_no_alias, _kind} -> [pin_num, "off"]
    end
  end

  def make_pins(%Sally.Device{pios: pios} = device, opts_map) do
    pin_opts = Map.get(opts_map, :pins, [:random])

    %{aliases: aliases} = Sally.Device.load_aliases(device)

    Enum.map(0..(pios - 1), fn pin_num ->
      Enum.find(aliases, :none, &match?(%{pio: ^pin_num}, &1)) |> make_pin(pin_num, pin_opts)
    end)
  end

  def make_pins(count, pin_opts) do
    Enum.map(0..(count - 1), fn pin -> [pin, cmd_from_opts(pin, pin_opts)] end)
  end

  def random_cmd, do: Enum.take_random(?a..?z, 8) |> to_string()

  def send_payload(cmd, opts) do
    preloads = [dev_alias: [device: [:host]]]
    Sally.Repo.preload(cmd, preloads) |> Sally.Command.Payload.send_cmd(opts)

    cmd
  end

  def track(exec_rc, cmd_args) do
    case exec_rc do
      {:busy, %Sally.Command{} = cmd} -> track_now(cmd, cmd_args)
      {:ok, cmd} -> cmd
    end
  end

  def track_now(%Sally.Command{} = cmd, args) do
    rc = Sally.Command.track(cmd, args)

    unless match?({:ok, pid} when is_pid(pid), rc) do
      raise("track failed: #{inspect(rc)}")
    end

    cmd
  end

  def detuple({_, cmd}), do: cmd
  def detuple(cmd), do: cmd
end
