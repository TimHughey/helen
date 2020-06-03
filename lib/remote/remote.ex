defmodule Remote do
  @moduledoc """
  The Remote module proveides the mapping from a Remote Device (aka MCR) hostname to
  a defined name and records various metadata about the remote device.
  """

  require Logger
  use Timex

  # alias Fact.RunMetric
  alias Fact.Remote.Boot

  alias Remote.Schemas.Remote, as: Schema
  alias Remote.DB.Remote, as: DB

  alias TimeSupport

  def browse do
    import Remote.DB.Remote, only: [all: 0]

    sorted = all() |> Enum.sort(fn a, b -> a.name <= b.name end)
    Scribe.console(sorted, data: [:id, :name, :host, :hw, :inserted_at])
  end

  def external_update(%{host: host, mtime: _mtime} = eu) do
    log = Map.get(eu, :log, true)

    result =
      :timer.tc(fn ->
        eu |> DB.add() |> send_remote_profile(eu)
      end)

    case result do
      {_t, {:ok, _rem}} ->
        # RunMetric.record(
        #   module: "#{__MODULE__}",
        #   metric: "external_update",
        #   # use the local name
        #   device: rem.name,
        #   val: t,
        #   record: false
        #   # record: Map.get(eu, :runtime_metrics, false)
        # )

        Fact.Remote.record(eu)

        :ok

      {_t, {err, details}} ->
        log &&
          Logger.warn([
            "external update failed host(",
            inspect(host, pretty: true),
            ") ",
            "err(",
            inspect(err, pretty: true),
            ") ",
            "details(",
            inspect(details, pretty: true),
            ")"
          ])

        :error
    end
  end

  def external_update(no_match) do
    log = is_map(no_match) and Map.get(no_match, :log, true)

    log &&
      Logger.warn([
        "external update received a bad map ",
        inspect(no_match, pretty: true)
      ])

    :error
  end

  @doc """
    Request OTA updates based on a prefix pattern

    Simply pipelines names_begin_with/1 and ota_update/2

      ## Examples
        iex> Schema.ota_names_begin_with("lab-", [])
  """
  @doc since: "0.0.11"
  def ota(pattern, opts \\ []) when is_binary(pattern) do
    import Remote.DB.Remote, only: [names_begin_with: 1]

    names_begin_with(pattern) |> ota_update(opts)
  end

  ###
  ###
  ### SPECIAL CASE FOR EASE OF OPERATIONS
  ###
  ###

  def ota_roost, do: "roost-" |> ota()
  def ota_lab, do: "lab-" |> ota()
  def ota_reef, do: "reef-" |> ota()
  def ota_test, do: "test-" |> ota()
  def ota_all, do: ["roost-", "lab-", "reef-", "test-"] |> ota()

  def restart(what, opts \\ []) do
    import Remote.DB.Remote, only: [remote_list: 1]

    opts = Keyword.put_new(opts, :log, false)
    restart_list = remote_list(what) |> Enum.filter(fn x -> is_map(x) end)

    if Enum.empty?(restart_list) do
      {:failed, restart_list}
    else
      opts = opts ++ [restart_list: restart_list]
      OTA.restart(opts)
    end
  end

  #
  # PRIVATE FUNCTIONS
  #

  defp ota_update(what, opts) do
    import Remote.DB.Remote, only: [remote_list: 1]

    opts = Keyword.put_new(opts, :log, false)
    update_list = remote_list(what) |> Enum.filter(fn x -> is_map(x) end)

    if Enum.empty?(update_list) do
      []
    else
      opts = opts ++ [update_list: update_list]
      OTA.send_cmd(opts)
    end
  end

  defp send_remote_profile([%Schema{} = rem], %{type: "boot"} = eu) do
    import Mqtt.SetProfile, only: [send_cmd: 1]

    send_cmd(rem)

    log = Map.get(eu, :log, true)

    if log do
      heap_free = (Map.get(eu, :heap_free, 0) / 1024) |> Float.round(1)
      heap_min = (Map.get(eu, :heap_min, 0) / 1024) |> Float.round(1)

      [
        inspect(rem.name),
        " BOOT ",
        Map.get(eu, :reset_reason, "no reset reason"),
        " ",
        eu.vsn,
        " ",
        inspect(Map.get(eu, :batt_mv, "0")),
        "mv ",
        inspect(Map.get(eu, :ap_rssi, "0")),
        "dB ",
        "heap(",
        inspect(heap_min),
        "k,",
        inspect(heap_free),
        "k) "
      ]
      |> Logger.info()
    end

    Boot.record(host: rem.name, vsn: eu.vsn, hw: eu.hw)

    # use the message mtime to update the last start at time
    eu = Map.put_new(eu, :last_start_at, TimeSupport.from_unix(eu.mtime))
    DB.update_from_external(rem, eu)
  end

  defp send_remote_profile([%Schema{} = rem], %{type: "remote"} = eu) do
    # use the message mtime to update the last seen at time
    eu = Map.put_new(eu, :last_seen_at, TimeSupport.from_unix(eu.mtime))
    DB.update_from_external(rem, eu)
  end

  defp send_remote_profile(_anything, %{type: type} = _eu),
    do:
      {:error, ["unknown message type=\"", type, "\""] |> IO.iodata_to_binary()}
end
