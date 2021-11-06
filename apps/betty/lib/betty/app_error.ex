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

  def record(module, tags) when is_atom(module) and is_list(tags) and tags != [] do
    new(module, tags) |> write()
  end

  def record(_, _), do: :bad_args
end
