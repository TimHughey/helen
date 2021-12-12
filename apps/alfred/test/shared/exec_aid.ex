defmodule Alfred.ExecAid do
  alias Alfred.{ExecCmd, ExecResult}

  def execute(cmd, opts \\ [])

  def execute(%ExecCmd{} = ec, _opts) do
    # when testing always echo unless explictly set to false
    echo = Keyword.get(ec.cmd_opts, :echo, true)
    if echo, do: Process.send(self(), {:echo, ec}, [])

    cmd_opts = ec.cmd_opts

    notify = cmd_opts[:notify_when_released] == true
    fields = [name: ec.name, will_notify_when_released: notify]
    er = struct(ExecResult, fields)

    case Alfred.NamesAid.binary_to_parts(ec.name) do
      %{rc: :ok} -> [rc: :ok, cmd: ec.cmd]
      %{rc: :pending = rc} -> [rc: rc, refid: "c87aeb", cmd: ec.cmd]
      %{expired_ms: x} when is_integer(x) -> [rc: {:ttl_expired, x}]
      _ -> []
    end
    |> then(fn fields -> struct(er, fields) end)
  end

  def execute(cmd_opts, opts)
      when is_list(cmd_opts) or is_map(cmd_opts)
      when is_list(opts) do
    ExecCmd.new(cmd_opts) |> execute(opts)
  end

  def exec_cmd_from_parts_add(%{exec_cmd_from_parts_add: _, parts: _} = ctx) do
    %{exec_cmd_from_parts: %ExecCmd{name: ctx.parts.name, cmd: ctx.parts.cmd}}
  end

  def exec_cmd_from_parts_add(_), do: :ok
end
