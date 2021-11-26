defmodule Rena.HoldCmd.StateAid do
  # alias Rena.{HoldCmd, Server}

  # defmacro assert_state(reply_tuple) do
  #   quote location: :keep, bind_quoted: [reply_tuple: reply_tuple] do
  #
  #
  #
  #   end
  # end
  #
  # def add_start_args(ctx) do
  #   case ctx do
  #     %{start_args_add: false} -> :ok
  #     %{start_args_add: opts} -> %{start_args: assemble_start_args(ctx, opts)}
  #     _ -> :ok
  #   end
  # end
  #
  #
  #
  #
  # def add(%{state_add: opts} = ctx) when is_list(opts) do
  #   start_args = assemble_start_args(ctx, opts)
  #   %{start: {_, _, [args]}} = Server.child_spec(start_args)
  #
  #   init_reply = Server.init(args)
  #   {:ok, state, _} = Should.Be.Tuple.with_size(init_reply, 3)
  #   Should.Be.struct(state, State)
  #
  #   state = Server.handle_continue(:bootstrap, state) |> Should.Be.Tuple.with_rc(:noreply)
  #
  #   Should.Be.struct(state, State)
  #
  #   %{state: state}
  # end
  #
  # def add(_), do: :ok
  #
  #
  # end
end
