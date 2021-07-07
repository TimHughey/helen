defmodule Sally.Immutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias __MODULE__

  alias Sally.{DevAlias, Device}
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
  def process(%Dispatch{category: "status"} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")
    Logger.debug("\n#{inspect(msg.data, pretty: true)}")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Ecto.Multi.run(:aliases, DevAlias, :load_aliases_with_last_cmd, [])
    |> Ecto.Multi.run(:aligned, Handler, :align_status, [msg])
    |> Ecto.Multi.run(:just_saw, Handler, :just_saw, [msg])
    |> Sally.Repo.transaction()
    |> check_result(msg)
    |> post_process()
    |> finalize()
  end

  @impl true
  def process(%Dispatch{category: "celsius", filter_extra: [_ident, _status]} = msg) do
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

  @impl true
  def post_process(%Dispatch{valid?: true} = msg) do
    msg
  end

  @impl true
  def post_process(%Dispatch{valid?: false} = msg), do: msg

  def add_datapoint(_repo, %{aliases: []} = _changes, %Dispatch{}) do
    # Logger.info("\n#{inspect(changes, pretty: true)}")

    {:ok, []}
  end

  def add_datapoint(repo, changes, %Dispatch{category: "celsius"} = msg) do
    alias Sally.Datapoint

    dev_alias = List.first(changes.aliases)
    datapoint = Ecto.build_assoc(dev_alias, :datapoints)

    changes = %{temp_c: msg.data[:val], reading_at: msg.sent_at}

    {:ok, Datapoint.changeset(datapoint, changes) |> repo.insert!(returning: true)}
  end

  def just_saw(repo, changes, %Dispatch{} = msg) do
    alias Alfred.JustSaw

    for %DevAlias{} = dev_alias <- changes.aliases, reduce: {:ok, []} do
      {:ok, acc} ->
        DevAlias.just_saw(repo, dev_alias, msg.sent_at)
        JustSaw.new(Sally, changes.device.mutable) |> JustSaw.add_device(dev_alias) |> Alfred.just_saw_cast()

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
