defmodule Sally.InboundMsg do
  def handoff_msg(%Sally.MsgIn{} = mo), do: mo
end
