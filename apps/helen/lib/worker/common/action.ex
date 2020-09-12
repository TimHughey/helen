defmodule Helen.Worker.Action.Common do
  @moduledoc false

  def action_token(action), do: get_in(action, [:token])
end
