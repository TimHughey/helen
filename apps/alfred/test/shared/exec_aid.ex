defmodule Alfred.ExecAid do
  alias Alfred.{ExecCmd, ExecResult}

  @type ctx_map :: %{optional(:make_exec_cmd) => list()}

  @callback execute(%ExecCmd{}, opts :: list()) :: %ExecResult{}
  @callback make_exec_cmd(ctx_map) :: %{optional(:exec_cmd) => %ExecCmd{}}

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      alias Alfred.ExecAid

      def execute(ec, opts \\ []), do: ExecAid.execute(ec, opts)
      def make_exec_cmd(ctx), do: ExecAid.make_exec_cmd(ctx)
    end
  end

  def execute(%ExecCmd{} = ec, _opts \\ []) do
    cmd_opts = ec.cmd_opts
    echo = if(cmd_opts[:echo] == true, do: true, else: false)

    if echo, do: Process.send(self(), {:echo, ec}, [])

    notify = cmd_opts[:notify_when_released] == true
    fields = [name: ec.name, will_notify_when_released: notify]
    er = struct(ExecResult, fields)

    case Alfred.NamesAid.to_parts(ec.name) do
      # %{rc: :ok, cmd: "echo"} -> [rc: :ok, cmd: ec.cmd]
      %{rc: :ok} -> [rc: :ok, cmd: ec.cmd]
      %{rc: :pending = rc} -> [rc: rc, refid: "c87aeb", cmd: ec.cmd]
      %{expired_ms: x} when is_integer(x) -> [rc: {:ttl_expired, x}]
      _ -> []
    end
    |> then(fn fields -> struct(er, fields) end)
  end

  def make_exec_cmd(ctx) do
    if is_map_key(ctx, :make_exec_cmd) and is_map_key(ctx, :parts) do
      ec = %ExecCmd{name: ctx.parts.name, cmd: ctx.parts.cmd}

      %{exec_cmd: ec}
    else
      :ok
    end
  end
end
