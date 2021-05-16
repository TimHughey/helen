defmodule Alfred.Immutable do
  alias Alfred.Types

  @callback exists?(Types.mutable_name()) :: boolean()
  @callback status(Types.name_or_id(), opts :: Types.optional_opts()) :: map()
end
