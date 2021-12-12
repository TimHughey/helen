defmodule Carol.StartArgsAid do
  @moduledoc """
  Creates start args for the Server
  """
  def add(%{start_args_add: opts} = ctx) when is_list(opts) do
    {via_init_args_fn, opts_rest} = Keyword.pop(opts, :init_args_fn, false)
    {want_keys, _} = Keyword.pop(opts_rest, :want, [])

    # start args must ALWAYS contain :id
    start_args = [id: ctx.server_name]

    # collect wanted init args from the context
    take_keys = want_keys ++ [:alfred, :equipment]
    init_args = Map.take(ctx, take_keys) |> Enum.into([])

    if via_init_args_fn do
      # add an anonymous function that returns the init args
      init_args_fn = fn opts_extra -> opts_extra ++ init_args end
      %{start_args: [init_args_fn: init_args_fn] ++ start_args}
    else
      # simply combine all args
      %{start_args: start_args ++ init_args}
    end
  end

  def add(_), do: :ok
end
