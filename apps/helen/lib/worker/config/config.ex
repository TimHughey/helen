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

        alias Helen.Worker.Config

        def config(what \\ :latest, config_txt \\ "")

        def config(version, _config_txt)
            when version in [:default, :latest, :previous] do
          Config.get(version, __MODULE__, @defaults_txt)
        end

        def config(:save, config_txt) when is_binary(config_txt) do
          Config.save(__MODULE__, config_txt)
        end

        def config(:save_default, _config_txt) do
          Config.save(__MODULE__, @defaults_txt)
        end
      end
    end
  end

  ##
  ## BEGIN OF Helen.Worker.Config MODULE
  ##

  alias Helen.Worker.Config.DB
  alias Helen.Worker.Config.Parser

  def get(:default, _mod_base, defaults_bin) when is_binary(defaults_bin) do
    Parser.parse(defaults_bin)
  end

  def get(version, module, defaults_bin) when is_binary(defaults_bin) do
    case DB.Config.as_binary(module, version) do
      x when is_binary(x) -> Parser.parse(x)
      :not_found -> Parser.parse(defaults_bin)
    end
  end

  def save(mod, raw) do
    import DB.Config, only: [module_to_binary: 1]

    case DB.Config.insert(module: module_to_binary(mod)) do
      {:ok, cfg} ->
        DB.Line.insert(cfg, raw)

      error ->
        error
    end
  end
end
