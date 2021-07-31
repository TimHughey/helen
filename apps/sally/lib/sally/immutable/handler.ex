defmodule Sally.Immutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias __MODULE__

  alias Sally.{Datapoint, DevAlias, Device}
  alias Sally.Dispatch

  @impl true
  def finalize(%Dispatch{} = msg) do
    %Dispatch{msg | final_at: DateTime.utc_now()}
    |> tap(fn
      %Dispatch{valid?: false} = x -> Logger.warn("\n#{inspect(x, pretty: true)}")
      %Dispatch{valid?: true} = x -> Logger.debug("\n#{inspect(x, pretty: true)}")
    end)
  end

  @impl true
  def process(%Dispatch{category: x, filter_extra: [_ident, "ok"]} = msg) when x in ["celsius", "relhum"] do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")
    Logger.debug("#{inspect(msg.filter_extra)} ==> #{inspect(msg.data, pretty: true)}")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Ecto.Multi.run(:aliases, DevAlias, :load_aliases, [])
    |> Ecto.Multi.run(:datapoint, Handler, :add_datapoint, [msg])
    |> Ecto.Multi.run(:just_saw, Handler, :just_saw, [msg])
    |> Sally.Repo.transaction()
    |> check_result(msg)
    |> post_process()
    |> finalize()
  end

  # ident encountered an error
  @impl true
  def process(%Dispatch{category: x, filter_extra: [ident, "error"]} = msg) when x in ["celsius", "relhum"] do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")
    Logger.debug("#{inspect(msg.filter_extra)} ==> #{inspect(msg.data, pretty: true)}")

    Betty.app_error(__MODULE__, ident: ident, immutable: true, hostname: msg.host.name)

    msg
    |> finalize()
  end

  @impl true
  def post_process(
        %Dispatch{valid?: true, results: %{aliases: [dev_alias], datapoint: %Datapoint{} = dp}} = msg
      ) do
    measurement = "immutables"
    tags = [name: dev_alias.name, family: msg.results.device.family]
    temp_f = (dp.temp_c * 9 / 5 + 32) |> Float.round(3)
    fields = [temp_c: dp.temp_c, temp_f: temp_f, read_us: msg.data.metrics["read"]]

    case dp do
      %Datapoint{relhum: nil} -> Betty.metric(measurement, fields, tags)
      %Datapoint{} -> Betty.metric(measurement, [relhum: dp.relhum] ++ fields, tags)
    end

    msg
  end

  @impl true
  def post_process(%Dispatch{valid?: true} = msg) do
    msg
  end

  @impl true
  def post_process(%Dispatch{valid?: false} = msg), do: msg

  # (1 of 2) when no aliases add no datapoints
  def add_datapoint(_repo, %{aliases: []} = _changes, %Dispatch{}) do
    {:ok, []}
  end

  # (2 of 2) ident has an alias, add the datapoint
  def add_datapoint(repo, changes, %Dispatch{category: "celsius"} = msg) do
    dev_alias = List.first(changes.aliases)
    datapoint = Ecto.build_assoc(dev_alias, :datapoints)

    changes = %{temp_c: msg.data[:val], reading_at: msg.sent_at}

    {:ok, Datapoint.changeset(datapoint, changes) |> repo.insert!(returning: true)}
  end

  # (3 of 3) ident has an alias, add the relhum datapoint
  def add_datapoint(repo, changes, %Dispatch{category: "relhum"} = msg) do
    dev_alias = List.first(changes.aliases)
    datapoint = Ecto.build_assoc(dev_alias, :datapoints)

    changes = %{temp_c: msg.data[:temp_c], relhum: msg.data[:relhum], reading_at: msg.sent_at}

    {:ok, Datapoint.changeset(datapoint, changes) |> repo.insert!(returning: true)}
  end

  def just_saw(repo, changes, %Dispatch{} = msg) do
    alias Alfred.JustSaw

    for %DevAlias{} = dev_alias <- changes.aliases, reduce: {:ok, []} do
      {:ok, acc} ->
        DevAlias.just_saw(repo, dev_alias, msg.sent_at)
        JustSaw.new(Sally, changes.device.mutable, dev_alias) |> Alfred.just_saw_cast()

        {:ok, [dev_alias] ++ acc}
    end
  end

  defp check_result(txn_result, %Dispatch{} = msg) do
    case txn_result do
      {:ok, results} -> %Dispatch{msg | valid?: true, results: results}
      {:error, e} -> Dispatch.invalid(msg, e)
    end
  end
end
