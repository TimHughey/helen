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
    |> Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Multi.run(:aliases, DevAlias, :load_aliases, [])
    |> Multi.run(:datapoint, DevAlias, :add_datapoint, [msg.data, msg.sent_at])
    |> Multi.run(:seen_list, DevAlias, :just_saw, [msg.sent_at])
    |> Repo.transaction()
  end

  @categories ["celsius", "relhum"]

  @impl true
  def process(%Dispatch{category: x, filter_extra: [_ident, "ok"]} = msg) when x in @categories do
    case db_actions(msg) do
      {:ok, %{device: device, seen_list: seen_list} = txn_results} ->
        # NOTE: alert Alfred of just seen names after txn is complete
        Sally.just_saw(device, seen_list) |> Dispatch.save_seen_list(msg) |> Dispatch.valid(txn_results)

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
