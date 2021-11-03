defmodule Alfred.Notify do
  @moduledoc """
  Alfred Notify Public API
  """

  @server Alfred.Notify.Server

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end

  def just_saw(opts), do: {:just_saw, opts} |> cast()

  @register_default_opts [frequency: [interval_ms: 0], link: true]
  @type notify_frequency_opts() :: nil | [interval_ms: pos_integer()] | :all
  @type register_opts() :: [pid: pid(), frequency: notify_frequency_opts]

  @spec register(register_opts()) :: {:ok, Alfred.NotifyTo.t()} | {:error, term()}
  def register(opts) when is_list(opts) do
    opts = Keyword.merge(@register_default_opts, opts)

    call({:register, opts})
  end

  @doc """
    Retrieve NotifyTo registrations

      iex> Alfred.Notify.registrations([all: true])

    Opts
      1. `all: true`    return all registrations (default)
      2. `name: binary` return registrations for a specific name
  """

  @type registrations_opts() :: [all: true, name: String.t()]
  @spec registrations(registrations_opts()) :: [Alfred.NotifyTo.t(), ...]
  def registrations(opts \\ [all: true]), do: {:registrations, opts} |> call()
  def unregister(ref) when is_reference(ref), do: {:unregister, ref} |> call()

  defp call(msg), do: (alive?() && GenServer.call(@server, msg)) || {:no_server, @server}
  defp cast(msg), do: (alive?() && GenServer.cast(@server, msg)) || {:no_server, @server}
end
