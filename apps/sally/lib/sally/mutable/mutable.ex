defmodule Sally.Mutable do
  require Logger
  require Ecto.Query

  alias Alfred.MutableStatus, as: MutStatus
  alias Ecto.Multi
  alias Sally.{Command, DevAlias, Device}

  @type changes_map() :: %{aliases: [Ecto.Schema.t(), ...]}
  @type cmd() :: String.t()
  @type pin() :: integer()
  @type pin_status() :: [pin() | cmd(), ...]
  @type pin_status_list() :: [pin_status(), ...]
  @type data_map() :: %{pins: pin_status_list()}
  @type seen_at :: DateTime.t()

  @doc """
  Create a list of `Ecto.Changeset` for the `DevAlias` present in the `Ecto.Multi` change map
  """
  @doc since: "0.5.10"
  @spec align_status_cs(changes_map, data_map, seen_at) :: Ecto.Multi.t()
  # (1 of 2) handle well formed changes map with a list of aliases
  def align_status_cs(%{aliases: [_ | _]} = changes, %{pins: _} = data, %DateTime{} = seen_at) do
    for %DevAlias{} = dev_alias <- changes.aliases, reduce: Multi.new() do
      acc ->
        multi_name = String.to_atom("aligned_#{dev_alias.pio}")

        case align_status_cs_one(dev_alias, data, seen_at) do
          %Ecto.Changeset{} = cs -> Multi.insert(acc, multi_name, cs, returning: true)
          :no_change -> acc
        end
    end
  end

  # (2 of 2) not well formed OR no aliases to consider
  def align_status_cs(_changes, _data, _seen_at), do: Multi.new()

  # NOTE: no guards required, only called by align_status_cs/3
  @doc """
  Create an `Ecto.Changeset` to align the `DevAlias` status to the reported status
  """
  @spec align_status_cs_one(Ecto.Schema.t(), data_map(), seen_at) :: Ecto.Changeset.t() | :nochange
  def align_status_cs_one(dev_alias, data, seen_at) do
    pin_cmd = pin_status(data.pins, dev_alias.pio)

    case status(dev_alias, []) do
      status when pin_cmd == :no_pin ->
        report_cmd_mismatch(dev_alias, status, :no_pin)

        :no_change

      # there's a cmd pending, don't get in the way of ack or ack timeout
      %MutStatus{pending?: true} ->
        :no_change

      # nothing to align, local cmd matches reported cmd
      %MutStatus{cmd: local_cmd} when local_cmd == pin_cmd ->
        :no_change

      # out of alignment
      %MutStatus{} = status ->
        report_cmd_mismatch(dev_alias, status, pin_cmd)

        Command.reported_cmd_changeset(dev_alias, pin_cmd, seen_at)
    end
  end

  @doc """
  Create a `Alfred.MutableStatus` for the specified name

  `Mutable.status` can be invoked with a variety of arguments depending on what
  information is available from the caller.

  ## Device Alias Name and Opts
  ```
  Sally.Mutable.status("device alias", [])
  ```

  ## Device Alias Schema, Device Schema and Opts

  The passed `Device` provides the `DateTime` to use for ttl expired check

  ```
  Mutable.status(%DevAlias{}, %Device{}, [])
  ```

  ## Device Alias Schema Only
  The associated `Device` will be loaded if needed

  ```
  Mutable.status(%DeviceAlias{}, [])
  ```

  ## Opts
  ```
  status("name", [ttl_ms: 1000])  # override %DevAlias{ttl_ms: _}

  status("name", [need_dev_alias: true])  # returns {%DevAlias{}, %MutableStatus{}}
  ```
  """
  @doc since: "0.5.10"
  @type ttl_ms() :: 50..600_000
  @type opts() :: [ttl_ms: ttl_ms(), need_dev_alias: boolean()]
  @type status_for() :: String.t() | Ecto.Schema.t()
  @type status_opts() :: [ttl_ms: pos_integer(), need_devalias: boolean()]
  @spec status(status_for(), status_opts()) :: MutStatus.t() | {Ecto.Schema.t() | MutStatus.t()}
  # (1 of 3) must lookup the DevAlias for name
  def status(name, opts) when is_binary(name) and is_list(opts) do
    case DevAlias.load_alias_with_last_cmd(name) do
      %DevAlias{} = x -> status(x, opts)
      _ -> MutStatus.not_found(name)
    end
  end

  # (2 o 3) just have DevAlias ensure Device is loaded and call status/3
  def status(%DevAlias{} = x, opts) when is_list(opts) do
    # NOTE: DevAlias.load_device/1 does not reload if device is already loaded
    dev_alias = DevAlias.load_device(x)

    status(dev_alias, dev_alias.device, opts)
  end

  # (3 of 3) calculate status since we have the DevAlias and Device
  def status(%DevAlias{} = dev_alias, %Device{} = device, opts) when is_list(opts) do
    # add the device last seen and updated at to opts for ttl_expired? calculation
    opts = [device_at: device.last_seen_at] ++ opts

    cond do
      ttl_expired?(dev_alias, opts) -> MutStatus.ttl_expired(dev_alias)
      pending?(dev_alias) -> MutStatus.pending(dev_alias)
      orphaned?(dev_alias) -> MutStatus.unresponsive(dev_alias)
      good?(dev_alias) -> MutStatus.good(dev_alias)
      :unmatched -> MutStatus.unknown_state(dev_alias)
    end
    |> MutStatus.finalize()
    |> make_response(dev_alias, opts)
  end

  @doc false
  def pin_status(pins, pin_num) do
    for [^pin_num, status] when is_binary(status) <- pins, reduce: :no_pin do
      _ -> status
    end
  end

  # when there is not a last Command there isn't a current command for the status.
  # to ensure there is a proper status an acked command is inserted to represent
  # the current cmd while processing messages from the remote host.

  defp good?(%DevAlias{cmds: []}), do: false
  defp good?(%DevAlias{cmds: [%Command{acked: true}]}), do: true

  defp make_response(res, dev_alias, opts) do
    if opts[:need_dev_alias], do: {dev_alias, res}, else: res
  end

  # (1 of 2) possible orphan
  defp orphaned?(%DevAlias{cmds: [%Command{orphaned: true, acked_at: acked_at}]} = dev_alias) do
    DateTime.compare(dev_alias.updated_at, acked_at) == :lt
  end

  # (2 of 2) never an orphan
  defp orphaned?(_dev_alias), do: false

  defp pending?(dev_alias) do
    case dev_alias do
      %DevAlias{cmds: [%Command{acked: false}]} -> true
      _ -> false
    end
  end

  defp report_cmd_mismatch(%DevAlias{} = da, %MutStatus{} = mut, pin_cmd) do
    tags = [
      align_status: true,
      mismatch: true,
      reported_cmd: pin_cmd,
      local_cmd: mut.cmd,
      status_error: mut.error,
      name: da.name
    ]

    Betty.app_error(__MODULE__, tags)
  end

  defp ttl_expired?(%DevAlias{updated_at: dev_alias_at} = dev_alias, opts) do
    # override DevAlias ttl_ms is specified
    ttl_ms = opts[:ttl_ms] || dev_alias.ttl_ms

    device_at = opts[:device_at]

    # calculate the ttl start DateTime
    ttl_start_at = DateTime.utc_now() |> DateTime.add(ttl_ms * -1, :millisecond)

    # DateTime.compare(ttl_start_at, device.last_seen_at) == :gt or
    #   DateTime.compare(ttl_start_at, dev_alias.updated_at) == :gt

    # ttl is expired when:
    #  1. dev_alias_at is before ttl_start_at
    #  2. device_at is before ttl_start_at
    Timex.before?(device_at, ttl_start_at) or Timex.before?(dev_alias_at, ttl_start_at)
  end
end
