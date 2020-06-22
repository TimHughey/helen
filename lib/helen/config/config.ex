defmodule Helen.Module.Config do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """

  @callback config_create(keyword() | [], binary() | <<>>) ::
              {:ok, module()} | {:failed, term}
  @callback config_merge(keyword()) :: {:ok, keyword()} | {:failed, term}
  @callback config_opts(keyword() | []) :: keyword() | [] | nil
  @callback config_put(keyword()) :: {:ok, keyword()} | {:failed, term}
  @callback config_update((keyword() -> keyword())) :: keyword()

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

      defoverridable config_create: 0
      defoverridable config_create: 1
      defoverridable config_create: 2

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
          _no_config_opts -> overrides
        end
      end

      defoverridable config_opts: 0
      defoverridable config_opts: 1

      @doc """
      Top level merges the options keyword list into the existing configuration record.

      If a configuration record does not exist one is created using the specified
      options.
      """
      @doc since: "0.0.27"
      def config_merge(opts) when is_list(opts) do
        alias Helen.Module.DB.Config

        opts = Keyword.drop(opts, [:__version__, :__available__])

        Config.merge(__MODULE__, opts)
      end

      defoverridable config_merge: 1

      @doc """
      Puts (replaces) the keyword list of options in the configuration record.

      Creates a configuration record if one does not exist.
      """
      @doc since: "0.0.27"
      def config_put(opts) when is_list(opts) do
        alias Helen.Module.DB.Config

        opts = Keyword.drop(opts, [:__version__, :__available__])

        Config.put(__MODULE__, opts)
      end

      defoverridable config_put: 1

      @doc """
      Executes the function passed and replaces the existing opts with the results.

      The function to execute takes one paramter (the existing opts) and must
      return a keyword list consisting of the updated opts.

      Creates a configuration record if one does not exist.
      """
      @doc since: "0.0.27"
      def config_update(func) when is_function(func) do
        alias Helen.Module.DB.Config

        opts =
          config_opts([])
          |> Keyword.drop([:__version__, :__available__])

        Config.put(__MODULE__, func.(opts))
      end

      defoverridable config_update: 1
    end
  end

  @doc """
  Show all Helen Module Config records
  """
  @doc since: "0.0.27"
  defdelegate all, to: Helen.Module.DB.Config
end
