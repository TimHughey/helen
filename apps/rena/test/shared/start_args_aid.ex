defmodule Rena.StartArgsAid do
  def add(ctx) do
    case ctx do
      %{start_args_add: false} -> :ok
      %{start_args_add: opts} -> %{start_args: assemble_args(ctx, opts)}
      _ -> :ok
    end
  end

  defp assemble_args(ctx, opts) do
    common_keys = [:alfred, :equipment]
    want_keys = ctx[:want_start_args] || []
    final_keys = common_keys ++ want_keys

    from_ctx = Map.take(ctx, final_keys) |> Enum.into([])

    for {k, v} <- ctx.start_args ++ from_ctx, reduce: opts do
      acc -> Keyword.put_new(acc, k, v)
    end
  end
end
