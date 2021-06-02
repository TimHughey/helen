defmodule Sally.MsgIn.Opts do
  require Logger

  alias __MODULE__
  alias Sally.Types, as: Types

  defstruct server: %{id: nil, name: nil, genserver: []}, callback_mod: nil

  @type t :: %__MODULE__{server: Types.server_info_map(), callback_mod: Types.module_or_nil()}

  def make_opts(mod, _start_opts, use_opts) do
    {id, rest} = Keyword.pop(use_opts, :id, mod)
    {name, genserver_opts} = Keyword.pop(rest, :name, mod)

    %Opts{server: %{id: id, name: name, genserver: genserver_opts}, callback_mod: mod}
    |> log_final_opts()
  end

  defp log_final_opts(%Opts{} = o) do
    Logger.debug(["final opts:\n", inspect(o, pretty: true)])
    o
  end
end
