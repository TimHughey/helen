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
      %Sally.DevAlias{} = dev_alias -> Sally.Command.latest(dev_alias, :id) |> cmd_from()
      %Sally.Command{acked: false} -> random_cmd()
      %Sally.Command{acked: true, orphaned: true} -> random_cmd()
      %Sally.Command{acked: true, cmd: cmd} -> cmd
      :none -> "off"
      _ -> "UNKNOWN"
    end
  end

  def dispatch(%{category: "cmdack"}, opts_map) do
    unless is_map_key(opts_map, :cmd_latest), do: raise(":cmd_latest is missing")

    execute = Enum.random(opts_map.cmd_latest)

    if not match?(%{rc: :pending}, execute), do: raise("cmd is not pending")

    # NOTE: pattern match because there are structs
    %{rc: :pending, detail: %{__execute__: %{refid: refid}}} = execute

    filter_extra = [refid]
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

  def historical(%Sally.DevAlias{} = dev_alias, opts_map) do
    %{history: count, _cmds_: cmd_args} = opts_map

    echo_opts = Map.take(cmd_args, [:echo]) |> Enum.into([])

    Enum.each(count..1, fn num ->
      cmd_opts = historical_cmd_opts(num, opts_map)
      cmd_args = [cmd: random_cmd(), cmd_opts: cmd_opts] ++ echo_opts

      case Sally.DevAlias.execute_cmd(dev_alias, cmd_args) do
        {:ok, %{acked: true} = execute} -> execute
        {:pending, %{acked: false}} = execute when num == 1 -> execute
        error_rc -> raise("execute error: #{inspect(error_rc, pretty: true)}")
      end
      |> tap(fn _execute -> Process.sleep(10) end)
    end)
  end

  @pending_kinds [:pending, :orphaned]

  def historical_cmd_opts(1 = _num, opts_map) do
    case opts_map do
      %{_cmds_: %{cmd_latest: kind}} when kind in @pending_kinds -> []
      _ -> [ack: :immediate]
    end
  end

  def historical_cmd_opts(_num, _opts_map), do: [ack: :immediate]

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
end
