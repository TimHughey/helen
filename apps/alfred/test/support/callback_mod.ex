defmodule Alfred.Test.CallbackMod do
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.ImmutableStatus
  alias Alfred.MutableStatus

  def execute(%ExecCmd{} = _ec) do
    %ExecResult{}
  end

  def status(type, name, opts \\ [])

  def status(:immutable, _name, _opts) do
    %ImmutableStatus{}
  end

  def status(:mutable, name, _opts) do
    case name do
      "Mutable Always On" = x -> make_good_mutable_status(x, "on")
      "Mutable Pending On" = x -> make_pending_mutable_status(x, "on")
      name -> %MutableStatus{name: name, found?: false}
    end
  end

  def make_good_mutable_status(name, cmd) do
    kn = Alfred.Names.lookup(name)

    MutableStatus.good(%{device: %{last_seen_at: kn.seen_at}, name: name, cmds: [%{cmd: cmd}]})
    |> Alfred.MutableStatus.finalize()
  end

  def make_pending_mutable_status(name, cmd) do
    MutableStatus.pending(%{name: name, cmds: [%{cmd: cmd, sent_at: DateTime.utc_now(), refid: "refid"}]})
    |> Alfred.MutableStatus.finalize()
  end
end
