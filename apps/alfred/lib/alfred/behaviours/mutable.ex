defmodule Alfred.Mutable do
  alias Alfred.Types

  @callback exists?(Types.mutable_name()) :: boolean()

  @callback execute(map()) :: Types.exec_result()
  @callback execute(Types.mutable_name(), Types.exec_map(), Types.exec_opts()) ::
              Types.exec_result()

  @callback on(Types.mutable_name_or_id(), Types.optional_opts()) :: Types.exec_result()
  @callback off(Types.mutable_name_or_id(), Types.optional_opts()) :: Types.exec_result()

  @callback status(Types.name_or_id(), opts :: Types.optional_opts()) :: map()
end
