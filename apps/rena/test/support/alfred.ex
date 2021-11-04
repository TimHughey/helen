defmodule Rena.Alfred do
  alias Alfred.ImmutableStatus, as: Status

  def status(name, _opts \\ []) do
    with [name, val_bin] when name != "bad" <- String.split(name),
         {temp_f, _} when is_float(temp_f) <- Float.parse(val_bin) do
      %Status{name: name, good?: true, datapoints: %{temp_f: temp_f}}
    else
      _ -> %Status{name: name}
    end
  end
end
