defmodule Helen.Module.Config do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """

  @callback config_create(keyword() | [], binary() | <<>>) ::
              {:ok, module()} | {:failed, term}
  @callback config_opts(keyword() | []) :: keyword() | [] | nil
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
      Dump the the Module configuration to a file (/tmp/<module>.exs)

      Returns the file containing the configuration dump.

      ## Examples

          iex> Helen.Module.Config.config_dump()
          :ok

      """
      @doc since: "0.0.27"
      def config_dump do
        alias Helen.Module.DB.Config

        opts =
          Config.opts(__MODULE__, [])
          |> Keyword.drop([:__available__, :__version__])

        filename =
          for part <- Module.split(__MODULE__) do
            String.downcase(part)
          end
          |> Enum.join("_")

        path_to_file = ["/tmp", "#{filename}.exs"] |> Path.join()

        contents = """
        opts = #{inspect(opts, pretty: true)}
        """

        File.write(path_to_file, contents, [:append])

        path_to_file
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
          _no_config_opts -> overrides
        end
      end

      defoverridable config_opts: 0
      defoverridable config_opts: 1

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

  @doc """
  Copies an existing module config applying an optional function to the copy

  ## Examples

      iex> Helen.Module.Config.copy(Reef.Temp.DisplayTank, Reef.Temp.MixTank)

  """
  @doc since: "0.0.27"
  def copy(from, to, func \\ & &1)
      when is_atom(from) and is_atom(to) and is_function(func) do
    alias Helen.Module.DB.Config

    opts =
      Config.opts(from, [])
      |> Keyword.drop([:__version__, :__available__])

    Config.put(to, func.(opts))
  end

  @doc """
  Delete a module config

  ## Examples

      iex> Helen.Module.Config.delete( Reef.Temp.MixTank)
      :ok
  """
  @doc since: "0.0.27"
  defdelegate delete(mod), to: Helen.Module.DB.Config
end
