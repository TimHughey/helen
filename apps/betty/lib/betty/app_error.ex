defmodule Betty.AppError do
  alias __MODULE__

  defstruct module: nil, tags: []

  @type t :: %AppError{module: module(), tags: nonempty_list()}

  def new(module, tags) when tags != [] do
    %AppError{module: module, tags: tags}
  end

  def write(%AppError{} = ae) do
    alias Betty.Metric

    fields = [error: true]
    tags = [module: ae.module] ++ ae.tags

    Metric.new("app_error", fields, tags) |> Metric.write()
  end
end
