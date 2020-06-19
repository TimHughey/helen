defmodule Helen.Module.Config do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """

  @callback config_create([opts: [...]] | [], binary() | <<>>) ::
              {:ok, module()} | {:failed, term}
  @callback config_opts(keyword() | []) :: keyword() | [] | nil
  @callback config_merge(keyword()) :: {:ok, keyword()} | {:failed, term}
  @callback config_put(keyword()) :: {:ok, keyword()} | {:failed, term}

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour Helen.Module.Config

      @doc """
      Create (or update) a new Module Configuration

      Takes two optional parametets:
      1. options to place into the configuration record (default: [])
      2. description of the configuration record (default: "<none>")
      """
      @doc since: "0.0.27"
      def config_create(opts \\ [], description \\ "<none>")
          when is_list(opts) and is_binary(description) do
        alias Helen.Module.DB.Config

        Config.create_or_update(__MODULE__, opts, description)
      end

      @doc """
      Returns the configuration opts for the Module.

      Takes an optional keyword list of overrides that are applied to the
      configuration record if found otherwise the overrides are returned
      unchanged.


      the configuration found parameter of

      If a configuraton record does not exist nil is returned regardless of
      any overrides.  In other words, overrides are only applied to an
      existing configuration record.
      """
      @doc since: "0.0.27"
      def config_opts(overrides \\ []) do
        alias Helen.Module.DB.Config

        overrides = [overrides] |> List.flatten()

        with opts when is_list(opts) <- Config.opts(__MODULE__, overrides) do
          opts
        else
          nil -> overrides
        end
      end

      @doc """
      Top level merges the options keyword list into the existing configuration record.

      If a configuration record does not exist one is created using the specified
      options.
      """
      @doc since: "0.0.27"
      def config_merge(opts) when is_list(opts) do
        alias Helen.Module.DB.Config

        Config.merge(__MODULE__, opts)
      end

      @doc """
      Puts (replaces) the keyword list of options in the configuration record.

      Creates a configuration record if one does not exist.
      """
      @doc since: "0.0.27"
      def config_put(opts) when is_list(opts) do
        alias Helen.Module.DB.Config

        Config.merge(__MODULE__, opts)
      end
    end
  end
end
