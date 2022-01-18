defmodule Alfred do
  @moduledoc """
  Master of known names
  """

  ##
  ## Alfred.Execute
  ##

  defdelegate execute(tuple), to: Alfred.Execute
  defdelegate execute(args, opts), to: Alfred.Execute
  defdelegate execute_off(name, opts \\ []), to: Alfred.Execute, as: :off
  defdelegate execute_on(name, opts \\ []), to: Alfred.Execute, as: :on
  defdelegate execute_toggle(name, opts \\ []), to: Alfred.Execute, as: :toggle
  defdelegate execute_to_binary(execute), to: Alfred.Execute, as: :to_binary

  ##
  ## Alfred.Name delegations
  ##

  defdelegate name_allowed_opts, to: Alfred.Name, as: :allowed_opts
  defdelegate name_available?(name), to: Alfred.Name, as: :available?
  defdelegate name_info(name), to: Alfred.Name, as: :info
  defdelegate name_missing?(name, opts \\ []), to: Alfred.Name, as: :missing?
  defdelegate name_registered?(name), to: Alfred.Name, as: :registered?
  defdelegate name_unregister(name), to: Alfred.Name, as: :unregister

  ##
  ## Alfred.Notify delegations
  ##

  defdelegate notify_register(opts), to: Alfred.Notify, as: :register
  defdelegate notify_unregister(opts), to: Alfred.Notify, as: :unregister

  ##
  ## Alfred.Status delegation
  ##

  defdelegate status(name, opts \\ []), to: Alfred.Status, as: :status
end
