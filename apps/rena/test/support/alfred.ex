defmodule Rena.Alfred do
  alias Alfred.ImmutableStatus, as: ImmutStatus
  alias Alfred.MutableStatus, as: MutStatus

  def status(name, opts \\ []) do
    case String.split(name) do
      ["mutable", _name, _cmd] -> mutable_status(name, opts)
      [_name, _val] -> immutable_status(name, opts)
    end
  end

  defp immutable_status(name, _opts) do
    with [name, val_bin] when name != "bad" <- String.split(name),
         {temp_f, _} when is_float(temp_f) <- Float.parse(val_bin) do
      %ImmutStatus{name: name, good?: true, datapoints: %{temp_f: temp_f}}
    else
      _ -> %ImmutStatus{name: name}
    end
  end

  defp mutable_status(name, _opts) do
    with [_mutable, name, cmd] when name != "bad" <- String.split(name),
         cmd when is_binary(cmd) <- cmd do
      %MutStatus{name: name, good?: true, cmd: cmd}
    else
      _ -> %MutStatus{name: name}
    end
  end
end