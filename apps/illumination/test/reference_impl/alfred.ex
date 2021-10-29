# simulates calls to Alfred register for notifications when the name is
# not found
defmodule AlfredNotFound do
  alias Alfred.NotifyTo

  def notify_register(name, _opts) do
    {:failed, "unknown name: #{name}"}
  end
end

defmodule AlfredFound do
  alias Alfred.NotifyTo

  def execute(%Alfred.ExecCmd{} = ec) do
    %Alfred.ExecResult{name: ec.name, cmd: ec.cmd}
  end

  def notify_register(name, _opts) do
    {:ok, %NotifyTo{name: name, ref: make_ref()}}
  end
end

defmodule AlfredNull do
  alias Alfred.{ExecCmd, ExecResult}

  def execute(%ExecCmd{name: name, cmd: cmd}), do: %ExecResult{name: name, cmd: cmd}
end

defmodule AlfredSendExecMsg do
  def execute(%Alfred.ExecCmd{} = ec) do
    Process.send(self(), ec, [])

    %Alfred.ExecResult{name: ec.name, cmd: ec.cmd, refid: "12345"}
  end
end
