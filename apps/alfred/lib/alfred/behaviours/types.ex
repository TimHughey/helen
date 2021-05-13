defmodule Alfred.Types do
  @type name_or_id :: String.t() | pos_integer()

  @type exec_map :: map()
  @type exec_opts :: keyword()
  @type exec_result :: {:pending, keyword()} | {:ok, map()}

  @type mutable_name() :: String.t()
  @type mutable_name_or_id() :: String.t() | pos_integer()

  @type optional_opts :: [] | keyword()
end
