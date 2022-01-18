defmodule Sally.Immutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias __MODULE__
  alias Sally.{Datapoint, DevAlias, Device}
  alias Sally.Dispatch

  def db_actions(%Dispatch{} = msg) do
    alias Ecto.Multi
    alias Sally.Repo

    Multi.new()
    |> Multi.put(:seen_at, msg.sent_at)
    |> Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Multi.run(:aliases, DevAlias, :load_aliases, [])
    |> Multi.run(:datapoint, DevAlias, :add_datapoint, [msg.data, msg.sent_at])
    |> Multi.update_all(:just_saw_db, fn x -> DevAlias.just_saw_db(x) end, [])
    |> Repo.transaction()
  end

  @categories ["celsius", "relhum"]

  @impl true
  def process(%Dispatch{category: x, filter_extra: [_ident, "ok"]} = msg) when x in @categories do
    case db_actions(msg) do
      {:ok, txn} ->
        :ok = Sally.DevAlias.just_saw(txn.aliases, seen_at: msg.sent_at)

        Dispatch.valid(msg, txn)

      {:error, :datapoint, error, _db_results} ->
        Dispatch.invalid(msg, error)
    end
  end

  # ident encountered an error
  @impl true
  def process(%Dispatch{category: x, filter_extra: [ident, "error"]} = msg) when x in @categories do
    Betty.app_error(__MODULE__, ident: ident, immutable: true, hostname: msg.host.name)

    Dispatch.valid(msg)
  end

  @impl true
  def post_process(%Dispatch{valid?: true, results: results} = msg)
      when is_map_key(results, :aliases)
      when is_map_key(results, :datapoint)
      when is_map_key(results, :device) do
    aliases_and_datapoints = Enum.zip(results.aliases, results.datapoint)

    measurement = "immutables"

    for {%DevAlias{} = dev_alias, %Datapoint{} = dp} <- aliases_and_datapoints, reduce: msg do
      %Dispatch{} = acc ->
        tags = [name: dev_alias.name, family: results.device.family]
        temp_f = (dp.temp_c * 9 / 5 + 32) |> Float.round(3)
        fields = [temp_c: dp.temp_c, temp_f: temp_f, read_us: msg.data.metrics["read"]]

        case dp do
          %Datapoint{relhum: nil} -> Betty.metric(measurement, fields, tags)
          %Datapoint{} -> Betty.metric(measurement, [relhum: dp.relhum] ++ fields, tags)
        end
        |> Dispatch.accumulate_post_process_results(acc)
    end
  end

  @impl true
  def post_process(dispatch), do: dispatch
end
