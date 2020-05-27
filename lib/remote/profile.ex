defmodule Remote.Profile do
  @moduledoc """

  Definition of Runtime Functionality for Remotes
  """

  alias Remote.Profile.Schema

  defdelegate create(name, opts \\ []), to: Schema
  defdelegate duplicate(name, new_name), to: Schema
  defdelegate find(name_or_id), to: Schema
  defdelegate reload(varies), to: Schema
  defdelegate names, to: Schema
  defdelegate to_external_map(name), to: Schema
  defdelegate update(name_or_schema, opts), to: Schema
  defdelegate lookup_key(key), to: Schema
end
