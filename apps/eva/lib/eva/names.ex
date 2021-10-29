defmodule Eva.Names do
  alias __MODULE__

  alias Alfred.NotifyTo

  defstruct needed: [], found: []

  def all_found?(%Names{needed: []}), do: true
  def all_found?(%Names{}), do: false

  def find_and_register(%Names{} = names) do
    # spin through the needed names accumulating names not found (yet)
    # and the notify registrations for those found
    for name <- names.needed, reduce: {%Names{names | needed: []}, []} do
      {%Names{} = names, notifies} ->
        # we want all notifications and to restart when Alfred restarts
        reg_rc = Alfred.notify_register(name, frequency: :all, link: true)

        case reg_rc do
          {:ok, %NotifyTo{} = nt} -> {add_found_name(names, name), [nt] ++ notifies}
          {:failed, _msg} -> {add_needed_name(names, name), notifies}
        end
    end
  end

  def new([name | _] = needed) when is_binary(name) do
    %Names{needed: needed}
  end

  defp add_found_name(%Names{} = names, name) do
    %Names{found: [name] ++ names.found}
  end

  defp add_needed_name(%Names{} = names, name) do
    %Names{needed: [name] ++ names.needed}
  end
end
