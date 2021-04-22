defmodule Garden.Server do
  @moduledoc false

  defmacro __using__(_opts) do
    # this modulw's context
    quote do
      # code injected into using module
      defmacro ensure_server_args(args) do
        # macro context of using module
        quote bind_quoted: [args: args, mod: __MODULE__] do
          # evaluated during using module compilation
          Garden.Server.ensure_server_args(args, mod)
        end
      end

      defmacro initial_state(args) do
        quote bind_quoted: [args: args, mod: __MODULE__] do
          Garden.Server.initial_state(args, mod)
        end
      end
    end
  end

  def ensure_server_args(args, mod) do
    import Keyword, only: [put_new: 3]

    put_new(args, :mod, mod) |> put_new(:name, mod)
  end

  def initial_state(args, mod) do
    args = ensure_server_args(args, mod)

    %{
      # mod: server_mod(args),
      mod: args[:mod],
      # name: server_name(args),
      name: args[:name],
      args: args,
      cfg: %{},
      opts: %{tz: "America/New_York", timeout: "PT1S", run_interval: "PT0.8S"},
      token: 0,
      ctrl_maps: []
    }
  end
end
