defmodule Lights.Config.Transforms do
  @moduledoc false

  def all do
    import Module, only: [concat: 1]
    base = ["Lights", "Config"]

    transforms = ["DurationTransform", "SunRefToDateTimeTransform", "ValueToAtomTransform"]

    for x <- transforms do
      List.flatten([base, x]) |> concat()
    end
  end
end

defmodule Lights.Config.DurationTransform do
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

defmodule Lights.Config.SunRefToDateTimeTransform do
  def transform(:sun_ref, val) when is_binary(val) do
    import Agnus, only: [sun_info: 1]

    sun_ref = String.to_atom(val)

    case sun_info(sun_ref) do
      %DateTime{} -> sun_ref
      x -> {:parse_fail, x}
    end
  end

  def transform(_k, v), do: v
end

defmodule Lights.Config.ValueToAtomTransform do
  def transform(key, v) when key in [:cmd, :sun_ref] and is_binary(v) do
    String.to_atom(v)
  end

  def transform(_k, v), do: v
end
