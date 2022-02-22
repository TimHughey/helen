defmodule Sally.DevAlias.Explain do
  @moduledoc false

  @all [latest: :cmds, status: :cmds, status: :datapoints, dev_alias: :load_aliases]
  def all do
    Enum.each(@all, fn {category, type} ->
      case {category, type} do
        {_, :cmds} -> "womb heater power"
        {_, :datapoints} -> "attic"
        {:dev_alias, :load_aliases} -> "front chandelier pwm"
      end
      |> query(category, type, [])
      |> IO.puts()
    end)
  end

  @default_opts [analyze: true, buffers: true, wal: true]
  def explain_opts(opts), do: Keyword.merge(opts, @default_opts)

  def query do
    """
      iex> Sally.explain(name, what, opts)

     name:      name of a Sally.DevAlias
     category:  :latest (for :cmds) | :status | :dev_alias
     type:      :cmds | :datapoints | :load_aliases
     opts:      explain opts (default: [analyze: true, buffers: true])
    """
  end

  def query(name, :latest, :cmds, opts) do
    module = Sally.Command
    dev_alias = Sally.Repo.get_by(Sally.DevAlias, name: name)

    module.latest_cmd_query(dev_alias)
    |> explain(opts)
    |> assemble_output(module, ".latest_cmd/2")
  end

  def query(name, :status, what, opts) do
    opts = explain_opts(opts)
    {explain_opts, query_opts} = Keyword.split(opts, Keyword.keys(@default_opts))

    module = if(what == :cmds, do: Sally.Command, else: Sally.Datapoint)

    module.status_query(name, query_opts)
    |> explain(explain_opts)
    |> assemble_output(module, ".status_query/2 (#{inspect(opts)})")
  end

  def query(<<_::binary>> = name, :dev_alias, :load_aliases, opts) do
    module = Sally.DevAlias

    dev_alias = Sally.Repo.get_by!(Sally.DevAlias, name: name)
    device = Sally.Repo.get_by!(Sally.Device, id: dev_alias.device_id)

    module.load_alias_query(device)
    |> explain(opts)
    |> assemble_output(module, ".load_aliases/2")
  end

  def explain(query, opts) do
    Sally.Repo.explain(:all, query, explain_opts(opts))
  end

  def assemble_output(raw, module, function) do
    ["\n", inspect(module), function, "\n", raw] |> IO.iodata_to_binary()
  end
end
