defmodule Helen.Module.Config do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """

  alias Helen.DB.Module.Config

  defdelegate create_or_update(mod, opts \\ [], description \\ ""), to: Config
  defdelegate eval_opts(mod, overrides \\ []), to: Config
  defdelegate find(module_or_id), to: Config
  defdelegate opts(module_or_id), to: Config
  defdelegate opts_merge(module_or_id, opts), to: Config
  defdelegate opts_put(module_or_id, opts), to: Config
end
