defmodule Helen.ModConfig do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      alias Helen.ModConfig
      # @behaviour Helen.ModConfig

      #   @doc """
      #   Is there an available configuraton?
      #
      #   Returns a boolean.
      #   """
      #   @doc since: "0.0.27"
      #   def config_available? do
      #     alias Helen.ModConfig
      #
      #     Config.available?(__MODULE__)
      #   end
      #
      #   @doc """
      #   Create (or update) a new Module Configuration
      #
      #   Takes two optional parametets:
      #   1. options to place into the configuration record (default: "")
      #   2. description of the configuration record (default: "<none>")
      #   """
      #   @doc since: "0.0.27"
      #   def config_create(config \\ "", description \\ "<none>")
      #       when is_binary(config) and is_binary(description) do
      #     alias Helen.ModConfig
      #
      #     Config.create_or_update(__MODULE__, config, description)
      #   end
      #
      #   defoverridable config_create: 0
      #   defoverridable config_create: 1
      #   defoverridable config_create: 2
      #
      #   @doc """
      #   Returns the configuration opts for the Module.
      #
      #   If a configuraton record does not exist an empty map is returned.
      #
      #   The caller must also check that the configuration record parsed
      #   correctly.
      #   """
      #   @doc since: "0.0.27"
      #   def config_opts() do
      #     alias Helen.Module.DB.Config
      #
      #     Config.parsed(__MODULE__)
      #   end
      #
      #   defoverridable config_opts: 0
      #
      #   @doc """
      #   Executes the function passed and replaces the existing opts with the results.
      #
      #   The function to execute takes one paramter (the existing opts) and must
      #   return a keyword list consisting of the updated opts.
      #
      #   Creates a configuration record if one does not exist.
      #   """
      #   @doc since: "0.0.27"
      #   def config_update(func) when is_function(func) do
      #     alias Helen.Module.DB.Config
      #
      #     opts =
      #       config_opts()
      #       |> Keyword.drop([:__version__, :__available__])
      #
      #     Config.put(__MODULE__, func.(opts))
      #   end
      #
      #   defoverridable config_update: 1
    end
  end

  alias Helen.Module.DB.Config

  @doc """
  Show all Helen Module Config records
  """
  @doc since: "0.0.27"
  defdelegate all, to: Helen.Module.DB.Config

  @doc """
  Is there an available configuraton?

  Returns a boolean.
  """
  @doc since: "0.0.27"
  def available?(module) do
    get_in(Config.parsed(module), [:__available__]) || false
  end

  @doc """
  Copies an existing module config applying an optional function to the copy

  ## Examples

      iex> Helen.ModConfig.copy(Reef.Temp.DisplayTank, Reef.Temp.MixTank)

  """
  @doc since: "0.0.27"
  def copy(from, to, func \\ & &1)
      when is_atom(from) and is_atom(to) and is_function(func) do
    opts =
      Config.opts(from, [])
      |> Keyword.drop([:__version__, :__available__])

    Config.put(to, func.(opts))
  end

  @doc delegate_to: {Config, :create_or_update, 3}
  @doc since: "0.0.27"
  defdelegate create_or_update(module, opts \\ [], description \\ "<none>"),
    to: Config

  @doc """
  Delete a module config

  ## Examples

      iex> Helen.ModConfig.delete( Reef.Temp.MixTank)
      :ok
  """
  @doc since: "0.0.27"
  defdelegate delete(mod), to: Config

  @doc delegate_to: {Config, :begin_with, 1}
  defdelegate modules_begin_with(pattern), to: Config, as: :begin_with

  @doc """
  Return the configuration opts for a module
  """
  def opts(module), do: Config.parsed(module)

  @doc """
  Return the parsed representation of a text configuration
  """
  @doc since: "0.0.27"
  def parsed(module), do: Config.parsed(module)
end
