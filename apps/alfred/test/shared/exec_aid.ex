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
    er = %ExecResult{name: ec.name}

    case Alfred.NamesAid.to_parts(ec.name) do
      %{rc: :ok, cmd: "echo"} -> %ExecResult{er | rc: :ok, cmd: ec.cmd}
      %{rc: :ok} -> %ExecResult{er | rc: :ok, cmd: ec.cmd}
      %{rc: :pending = rc} -> %ExecResult{er | rc: rc, refid: make_ref(), cmd: ec.cmd}
      _ -> er
    end
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
