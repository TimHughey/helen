defmodule Carol.StartArgsAid do
  @moduledoc false

  def add(%{start_args_add: {:app, app, module, instance}}) do
    %{
      child_spec: Carol.Instance.child_spec({app, module, instance}, []),
      server_name: Carol.Instance.id({module, instance}),
      start_args: Carol.Instance.start_args({app, module, instance})
    }
  end

  def add(_), do: :ok
end
