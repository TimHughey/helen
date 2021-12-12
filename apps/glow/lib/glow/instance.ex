defmodule Glow.Instance do
  @moduledoc """
  Glow instance assistant

  """

  @doc """
  Create the id of a `Glow.Instance`

  ## Example
  ```
  # from an atom
  :greenhouse |> Glow.Instance.id()
  #=> Glow.Greenhouse

  ```
  """
  @doc since: "0.1.0"
  @spec id(atom()) :: module()
  def id(instance) when is_atom(instance) do
    suffix = to_string(instance) |> Macro.camelize()

    ["Glow", suffix] |> Module.concat()
  end

  @doc """
  Create the module name of a `Glow.Instance`

  ## Example
  ```
  # from an atom
  :greenhouse |> Glow.Instance.module()
  #=> Glow.Instance.Greenhouse

  ```
  """
  @doc since: "0.1.0"
  @spec module(atom()) :: module()
  def module(instance) when is_atom(instance) do
    suffix = to_string(instance) |> Macro.camelize()

    ["Glow", "Instance", suffix] |> Module.concat()
  end

  @doc """
  Short name of an instance

  ```
  code
  ```
  """
  @doc since: "0.1.0"
  def display_name(instance) when is_atom(instance) do
    id = Module.split(instance) |> List.last()

    case id do
      "FrontEvergreen" -> "Evergreen"
      "FrontChandelier" -> "Chandelier"
      "FrontRedMaple" -> "Red Maple"
      x -> x
    end
  end

  @doc """
  Summary

  ```
  code
  ```
  """
  @doc since: "0.1.0"
  def start_args(instance) when is_atom(instance) do
    alias Glow.Instance

    id = Instance.id(instance)
    init_args_fn = &Instance.module(instance).init_args/1

    [id: id, init_args_fn: init_args_fn]
  end

  # @doc since: "0.1.0"
  # defmacro start_args(instance) when is_atom(instance) do
  #   quote location: :keep, bind_quoted: [instance: instance] do
  #     alias Glow.Instance
  #
  #     id = Instance.id(instance)
  #     init_args_fn = &Instance.module(instance).init_args/1
  #
  #     [id: id, init_args_fn: init_args_fn]
  #   end
  # end
end
