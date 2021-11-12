defmodule AlfredSim do
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.ImmutableStatus, as: ImmutStatus
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.Notify.Ticket

  def execute(%ExecCmd{} = ec, _opts \\ []) do
    case String.split(ec.name) do
      [_mutable, "bad", cmd] -> %ExecResult{name: ec.name, rc: {:ttl_expired, 10_000}, cmd: cmd}
      [_mutable, "pending", cmd] -> %ExecResult{name: ec.name, rc: :pending, cmd: cmd, refid: "123456"}
      [_mutable, _name, cmd] -> %ExecResult{name: ec.name, rc: :ok, cmd: cmd}
    end
  end

  def notify_register(opts) do
    %Ticket{name: opts[:name], ref: make_ref()}
  end

  def status(name, opts \\ []) do
    case String.split(name) do
      ["mutable", _name, _cmd] -> mutable_status(name, opts)
      [_name, _val] -> immutable_status(name, opts)
    end
  end

  defp immutable_status(name, _opts) do
    with [name, val_bin] when name != "bad" <- String.split(name),
         {temp_f, _} when is_float(temp_f) <- Float.parse(val_bin) do
      %ImmutStatus{name: name, good?: true, datapoints: %{temp_f: temp_f}}
    else
      _ -> %ImmutStatus{name: name}
    end
  end

  defp mutable_status(name, _opts) do
    with [_mutable, name, cmd] when name != "bad" <- String.split(name),
         cmd when is_binary(cmd) <- cmd do
      %MutStatus{name: name, good?: true, cmd: cmd}
    else
      _ -> %MutStatus{name: name}
    end
  end

  def parse_name(name) do
    re = ~r/^(?<type>\w+)\s([\w\d_]+)\s(?<rc>[\w\d_]+)\s(?<data>[\w\d._\s]+)$/

    captures = Regex.named_captures(re, name)

    for {k, v} <- captures, into: %{}, do: {String.to_atom(k), v}
  end
end
