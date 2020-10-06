defmodule Helen.Worker.Opts do
  @moduledoc """
  Provides standard functionality for a Worker's Config (Opts)
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      mod_base = Module.split(__MODULE__) |> Enum.drop(-1) |> Module.concat()

      defmodule Module.concat(mod_base, "Opts") do
        @defaults_file Path.join([__DIR__, "..", "opts", "defaults_v2.txt"])
        @external_resource @defaults_file
        @defaults_txt File.read!(@defaults_file)

        def default_opts, do: @defaults_txt

        def parsed(raw \\ nil) do
          alias Helen.Worker.Config, as: Parser

          if is_nil(raw) or raw === "" do
            default_opts() |> Parser.parse()
          else
            raw |> Parser.parse()
          end
        end
      end
    end
  end
end
