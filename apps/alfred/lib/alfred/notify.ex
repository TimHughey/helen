defmodule Alfred.Notify do
  @moduledoc """
  Alfred Notify Public API
  """

  alias Alfred.KnownName

  @server Alfred.Notify.Server

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end

  def just_saw(%KnownName{} = kn), do: {:just_saw, kn} |> cast()

  @register_default_opts [frequency: [interval_ms: 0], link: true]
  @type notify_frequency_opts() :: nil | [interval_ms: pos_integer()] | :all | :use_ttl
  @type register_opts() :: [pid: pid(), frequency: notify_frequency_opts]
  @spec register(String.t(), register_opts()) :: {:ok, NotifyTo.t()} | {:error, term()}

  def register(name, opts) do
    alias Alfred.{KnownName, Names}

    opts = Keyword.merge(@register_default_opts, opts)

    case Names.lookup(name) do
      %KnownName{missing?: false} = kn -> {:register, kn, opts} |> call()
      _ -> {:failed, "unknown name: #{name}"}
    end
  end

  def registrations, do: {:registrations} |> call()
  def unregister(ref) when is_reference(ref), do: {:unregister, ref} |> call()

  defp call(msg), do: (alive?() && GenServer.call(@server, msg)) || {:no_server, @server}
  defp cast(msg), do: (alive?() && GenServer.cast(@server, msg)) || {:no_server, @server}
end
