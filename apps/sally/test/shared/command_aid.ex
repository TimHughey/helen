defmodule Sally.CommandAid do
  @moduledoc """
  Supporting functionality for creating Sally.Command for testing
  """

  def cmd_from_opts(pin, pin_opts) do
    Enum.reduce(pin_opts, random_cmd(), fn {pin_num, cmd}, acc ->
      if(pin == pin_num, do: cmd, else: acc)
    end)
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

  def make_pins(count, pin_opts) do
    Enum.map(0..(count - 1), fn pin -> [pin, cmd_from_opts(pin, pin_opts)] end)
  end

  def random_cmd, do: Ecto.UUID.generate() |> String.split("-") |> Enum.at(2)
end
