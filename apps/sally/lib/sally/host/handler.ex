defmodule Sally.Host.Handler do
  require Logger

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias Sally.Dispatch
  alias Sally.Host
  alias Sally.Host.ChangeControl
  alias Sally.Host.Instruct

  @impl true
  def finalize(%Dispatch{} = msg) do
    log = fn x ->
      Logger.debug("\n#{inspect(x, pretty: true)}")
      x
    end

    %Dispatch{msg | final_at: DateTime.utc_now()} |> log.()
  end

  @impl true
  def process(%Dispatch{category: cat} = msg) when cat in ["startup", "boot", "run"] do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    cc = assemble_change_control(msg)

    Logger.debug("\n#{inspect(cc, pretty: true)}")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:host, Host.changeset(cc), Host.insert_opts(cc.replace))
    |> Sally.Repo.transaction()
    |> check_result(msg)
    |> post_process()
    |> finalize()
  end

  # @impl true
  # def process(%Dispatch{} = msg) do
  #   Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")
  #
  #   Ecto.Multi.new()
  #   |> Ecto.Multi.insert(:host, Host.changeset(msg), Host.insert_opts())
  #   |> Sally.Repo.transaction()
  #   |> check_result(msg)
  #   |> post_process()
  #   |> finalize()
  # end

  @impl true
  def post_process(%Dispatch{valid?: false} = msg), do: msg

  @impl true
  def post_process(%Dispatch{category: "startup"} = msg) do
    profile = Host.boot_payload_data(msg.host)
    pname = profile["meta"]["name"]
    pdesc = profile["meta"]["description"]

    Logger.debug("host=#{msg.host.name} startup; sending profile='#{pname}' description='#{pdesc}'")

    %Instruct{
      ident: msg.ident,
      name: msg.host.name,
      subsystem: "host",
      # the description could be long, don't send it
      data: %{profile | "meta" => Map.delete(profile["meta"], :description)},
      filters: ["profile", msg.host.name]
    }
    |> Instruct.send()

    msg
  end

  @impl true
  def post_process(%Dispatch{category: "boot"} = msg) do
    Logger.debug(inspect(msg.data, pretty: true))
    boot_profile = List.first(msg.filter_extra, "unknown")
    Logger.debug("host=#{msg.host.name} profile='#{boot_profile}' startup complete")

    stack_size = msg.data[:stack]["size"] || 1
    stack_hw = msg.data[:stack]["highwater"] || 1
    stack_used = (100.0 - stack_hw / stack_size * 100.0) |> Float.round(2)

    %Betty.Metric{
      measurement: "host",
      tags: %{ident: msg.host.ident, name: msg.host.name},
      fields: %{
        boot_elapsed_ms: msg.data[:elapsed_ms] || 0,
        tasks: msg.data[:tasks] || 0,
        stack_size: stack_size,
        stack_high_water: stack_used,
        stack_used: stack_used
      }
    }
    |> Betty.write_metric()

    msg
  end

  # @impl true
  # def post_process(%Dispatch{category: "log"} = msg) do
  #   msg
  # end
  #
  # @impl true
  # def post_process(%Dispatch{category: "ota"} = msg) do
  #   msg
  # end

  @impl true
  def post_process(%Dispatch{category: "run"} = msg) do
    Logger.debug(inspect(msg.data, pretty: true))

    %Betty.Metric{
      measurement: "host",
      tags: %{ident: msg.host.ident, name: msg.host.name},
      fields: %{
        ap_primary_channel: msg.data[:ap]["pri_chan"] || 0,
        ap_rssi: msg.data[:ap]["rssi"] || 0,
        heap_min: msg.data.heap["min"],
        heap_max_alloc: msg.data.heap["max_alloc"],
        heap_free: msg.data.heap["free"]
      }
    }
    |> Betty.write_metric()

    msg
  end

  # Dispatches for different categories define specific changes to the Host record
  # (1 of 2) startup messages
  defp assemble_change_control(%Dispatch{category: "startup"} = msg) do
    raw_changes = %{
      ident: msg.ident,
      name: msg.ident,
      firmware_vsn: msg.data[:firmware_vsn],
      idf_vsn: msg.data[:idf_vsn],
      app_sha: msg.data[:app_sha],
      build_at: make_build_datetime(msg.data),
      last_start_at: msg.sent_at,
      last_seen_at: msg.sent_at,
      reset_reason: msg.data[:reset_reason]
    }

    %ChangeControl{
      raw_changes: raw_changes,
      required: Map.keys(raw_changes),
      # never replace the ident, it is the conflict field
      replace: raw_changes |> Map.drop([:ident, :name, :inserted_at]) |> Map.keys()
    }
  end

  # (2 of 2) boot and run time metrics
  defp assemble_change_control(%Dispatch{category: cat} = msg) when cat in ["boot", "run"] do
    raw_changes = %{
      ident: msg.ident,
      name: msg.ident,
      last_start_at: msg.sent_at,
      last_seen_at: msg.sent_at
    }

    %ChangeControl{
      raw_changes: raw_changes,
      required: Map.keys(raw_changes),
      # never replace the ident, it is the conflict field
      replace: [:last_seen_at]
    }
  end

  defp check_result(txn_result, %Dispatch{} = msg) do
    case txn_result do
      {:ok, results} -> %Dispatch{msg | host: results.host}
      {:error, e} -> Dispatch.invalid(msg, e)
    end
  end

  @months ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  defp make_build_datetime(%{build_date: build_date, build_time: build_time}) do
    [month_bin, day, year] = String.split(build_date, " ", trim: true)
    month = Enum.find_index(@months, fn x -> x == month_bin end) + 1

    date = Date.new!(String.to_integer(year), month, String.to_integer(day))
    time = Time.from_iso8601!("#{build_time}.049152Z")

    DateTime.new!(date, time, "America/New_York")
  end
end
