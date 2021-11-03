defmodule AlfredFound do
  alias Alfred.NotifyTo

  def execute(%Alfred.ExecCmd{} = ec) do
    %Alfred.ExecResult{name: ec.name, cmd: ec.cmd}
  end

  def notify_register(opts) do
    name = opts[:name]
    {:ok, %NotifyTo{name: name, ref: make_ref()}}
  end
end

defmodule AlfredNull do
  alias Alfred.{ExecCmd, ExecResult}

  def execute(%ExecCmd{name: name, cmd: cmd}), do: %ExecResult{name: name, cmd: cmd}
end

# NOTE: sends a message to the calling process containing the ExecCmd passed.
# this message is received in test cases to validate the ExecCmd
defmodule AlfredSendExecMsg do
  alias Alfred.{ExecCmd, ExecResult, NotifyTo}

  def execute(%ExecCmd{} = ec) do
    Process.send(self(), ec, [])

    %ExecResult{name: ec.name, cmd: ec.cmd, refid: "12345"}
  end

  def notify_register(opts) do
    name = opts[:name]
    {:ok, %NotifyTo{name: name, ref: make_ref()}}
  end
end

defmodule AlfredAlwaysOn do
  def status(name) do
    %Alfred.MutableStatus{name: name, good?: true, cmd: "on"}
  end
end

defmodule AlfredAlwaysPending do
  def status(name) do
    %Alfred.MutableStatus{name: name, good?: true, pending?: true, cmd: "on"}
  end
end
