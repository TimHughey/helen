defmodule Sally.DevAlias.Explain do
  @moduledoc false

  @default_opts [analyze: true, buffers: true, wal: true]
  def explain_opts(opts), do: Keyword.merge(opts, @default_opts)

  def query do
    """
      iex> Sally.explain(name, what, opts)

     name:      name of a Sally.DevAlias
     category:  :status | :cmdack (only for type: :cmds)
     type:      :cmds or :datapoints
     opts:      explain opts (default: [analyze: true, buffers: true])
    """
  end

  def query(name, :cmdack, :cmds, opts) do
    module = Sally.Command

    Sally.Repo.get_by(Sally.DevAlias, name: name)
    |> module.latest_query(:id)
    |> then(fn query -> Sally.Repo.explain(:all, query, explain_opts(opts)) end)
    |> then(fn output -> ["\n", inspect(module), ".latest_query/1", "\n", output] end)
    |> IO.iodata_to_binary()
  end

  def query(name, :status, what, opts) do
    opts = explain_opts(opts)
    {explain_opts, query_opts} = Keyword.split(opts, Keyword.keys(@default_opts))

    module =
      case what do
        :cmds -> Sally.Command
        :datapoints -> Sally.Datapoint
      end

    module.status_query(name, query_opts)
    |> then(fn query -> Sally.Repo.explain(:all, query, explain_opts) end)
    |> then(fn output -> ["\n", inspect(module), ".status_query/2", "\n", output] end)
    |> IO.iodata_to_binary()
  end
end
