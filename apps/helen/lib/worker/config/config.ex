defmodule Helen.Worker.Config do
  @moduledoc """
  Provides standard functionality for a Worker's Config (Opts)
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      mod_base = Module.split(__MODULE__) |> Enum.drop(-1) |> Module.concat()

      defmodule Module.concat(mod_base, "Config") do
        @defaults_file Path.join([__DIR__, "..", "opts", "defaults_v2.txt"])
        @external_resource @defaults_file
        @defaults_txt File.read!(@defaults_file)

        def default_opts, do: @defaults_txt

        def config(what \\ :latest, config_txt \\ "")
            when is_atom(what) and is_binary(config_txt) do
          alias Helen.Worker.Config
          alias Helen.Worker.Config.Parser

          case what do
            :latest -> Config.latest(defaults: @defaults_txt)
            :default -> @defaults_txt |> Parser.parse()
          end
        end

        def parsed(raw \\ nil) do
          alias Helen.Worker.Config.Parser

          if is_nil(raw) or raw === "" do
            default_opts() |> Parser.parse()
          else
            raw |> Parser.parse()
          end
        end
      end
    end
  end

  ##
  ## BEGIN OF Helen.Worker.Opts MODULE
  ##

  alias Helen.Worker.Config
  alias Helen.Worker.Config.Parser

  def latest(opts) do
    opts[:defaults] |> Parser.parse()
  end
end
