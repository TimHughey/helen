defmodule Carol.StartArgsAid do
  @moduledoc """
  Creates start args for the Server
  """

  def add(%{start_args_add: {:app, app, module, instance}}) do
    %{
      child_spec: Carol.Instance.child_spec({app, module, instance}, []),
      server_name: Carol.Instance.id({module, instance}),
      start_args: Carol.Instance.start_args({app, module, instance})
    }
  end

  def add(%{start_args_add: {:new_app, app, module, instance}} = ctx) do
    # simulate app config
    args = [
      opts: [alfred: AlfredSim, timezone: "America/New_York"],
      instances: [
        {instance,
         [
           equipment: ctx.equipment,
           episodes: ctx.episodes
         ]}
      ]
    ]

    Application.put_env(app, module, args)

    %{
      child_spec: Carol.Instance.child_spec({app, module, instance}, []),
      server_name: Carol.Instance.id({module, instance}),
      start_args: Carol.Instance.start_args({app, module, instance})
    }
  end

  def add(_), do: :ok
end
