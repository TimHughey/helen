defmodule Garden.Config.Transforms do
  @moduledoc false

  def all do
    [
      Garden.Config.Transform.Duration
      #  Garden.Config.Transform.SunRefToDateTime
      #  Garden.Config.Transform.ValueToAtom
    ]
  end
end

defmodule Garden.Config.Transform.Duration do
  @moduledoc false

  use Timex
  use Toml.Transform

  def transform(key, v) when key in [:plus, :minus] and is_binary(v) do
    case Duration.parse(v) do
      {:ok, duration} -> duration
      x -> {:parse_fail, x}
    end
  end

  def transform(_k, v), do: v
end

# defmodule Garden.Config.Transform.SunRefToDateTime do
# def transform(:sun_ref, val) when is_binary(val) do
#   case Solar.event(val) do
#     %DateTime{} = sun_ref -> sun_ref
#     x -> {:parse_fail, x}
#   end
# end
#
# def transform(_k, v), do: v
# end
#
# defmodule Garden.Config.Transform.ValueToAtom do
# def transform(key, v) when key in [:cmd, :sun_ref] and is_binary(v) do
#   String.to_atom(v)
# end
#
# def transform(_k, v), do: v
# end
