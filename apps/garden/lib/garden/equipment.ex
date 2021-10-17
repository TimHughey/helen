defmodule Garden.Equipment.Irrigation.Garden do
  use Eva
end

defmodule Garden.Equipment.Irrigation.Porch do
  use Eva
end

defmodule Garden.Equipment.Irrigation.Power do
  use Eva
end

defmodule Garden.Equipment.Lighting.Evergreen do
  use Eva
end

defmodule Garden.Equipment.Lighting.RedMaple do
  use Eva
end

defmodule Garden.Equipment.Lighting.Chandelier do
  use Eva
end

defmodule Garden.Equipment.Lighting.Greenhouse do
  use Eva
end

defmodule Garden.Equipment.Check do
  alias __MODULE__

  alias Alfred.MutableStatus, as: Status

  defstruct needed: [], ready: []

  def all_good?(%Check{needed: []}), do: true
  def all_good?(%Check{}), do: false

  def check_status(%Check{} = names) do
    # spin through the needed names accumulating names where the equipment status isn't ready
    for name <- names.needed, reduce: %Check{names | needed: []} do
      %Check{} = names ->
        # we want all notifications and to restart when Alfred restarts
        status_rc = Alfred.status(name)

        case status_rc do
          %Status{good?: true} -> add_good_status(names, name)
          _ -> add_needed_name(names, name)
        end
    end
  end

  def new([name | _] = needed) when is_binary(name) do
    %Check{needed: needed}
  end

  defp add_good_status(%Check{ready: ready} = names, name) do
    %Check{names | ready: [name] ++ ready}
  end

  defp add_needed_name(%Check{needed: needed} = names, name) do
    %Check{names | needed: [name] ++ needed}
  end
end
