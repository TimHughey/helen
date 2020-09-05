defmodule PulseWidth do
  @moduledoc """
    The PulseWidth module provides the public API for PulseWidth devices.
  """

  require Logger
  use Timex

  alias PulseWidth.Command.Example
  alias PulseWidth.DB.{Alias, Command, Device}
  alias PulseWidth.Notify

  @doc """
    Public API for creating a PulseWidth Alias
  """
  @doc since: "0.0.26"
  def alias_create(device_or_id, name, opts \\ []) do
    # first, find the device to alias
    with %Device{device: dev_name} = dev <- device_find(device_or_id),
         # create the alias and capture it's name
         {:ok, %Alias{name: name}} <- Alias.create(dev, name, opts) do
      [created: [name: name, device: dev_name]]
    else
      nil -> {:not_found, device_or_id}
      error -> error
    end
  end

  @doc """
  Finds a PulseWidth alias by name or id
  """

  @doc since: "0.0.25"
  defdelegate alias_find(name_or_id), to: Alias, as: :find

  @doc """
  Set all PulseWidth aliased devices to off
  """
  @doc since: "0.0.25"
  defdelegate all_off, to: Alias

  @doc """
    Send a basic sequence to a PulseWidth found by name or actual struct

    PulseWidth.basic(name, basic: %{})
  """
  @doc since: "0.0.27"
  def basic(name_id_pwm, cmd_map, opts \\ []) do
    Alias.cmd_direct(name_id_pwm, cmd_map, opts)
  end

  @doc """
    Return a keyword list of the PulseWidth command counts
  """
  @doc since: "0.0.24"
  defdelegate cmd_counts, to: Command

  @doc """
    Reset the counts maintained by Command (Broom)
  """
  @doc since: "0.0.24"
  defdelegate cmd_counts_reset(opts), to: Command

  @doc """
    Return a list of the PulseWidth commands tracked
  """
  @doc since: "0.0.24"
  defdelegate cmds_tracked, to: Command

  @doc """
    Public API for deleting a PulseWidth Alias
  """
  @doc since: "0.0.25"
  defdelegate delete(name_or_id), to: Alias, as: :delete

  @doc """
    Find a PulseWidth Device by device or id
  """
  @doc since: "0.0.25"
  defdelegate device_find(device_or_id), to: Device, as: :find

  @doc """
    Find the alias of a PulseWidth device
  """
  @doc since: "0.0.25"
  defdelegate device_find_alias(device_or_id), to: Device

  @doc """
    Retrieve a list of PulseWidth devices that begin with a pattern
  """
  @doc since: "0.0.25"
  def devices_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(x in Device,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
  end

  def duty(name, opts \\ [])

  def duty(name, val) when is_binary(name) and is_number(val),
    do: Alias.duty(name, duty: val)

  defdelegate duty(name, opts), to: Alias
  defdelegate duty_names_begin_with(patterm, opts \\ []), to: Alias

  @doc delegate_to: {Example, :cmd, 2}
  defdelegate example_cmd(type \\ :random, opts \\ []), to: Example, as: :cmd

  @doc """
    Execute an action
  """
  @doc since: "0.0.27"
  def execute_action(%{worker_cmd: cmd, worker: %{name: name}} = action) do
    case cmd do
      :on -> on(name)
      :off -> off(name)
      :duty -> duty(name, action[:float])
      _cmd -> random(name, action[:custom])
    end
  end

  @doc delegate_to: {Alias, :exists?, 1}
  defdelegate exists?(name), to: Alias

  @doc """
    Handles all aspects of processing messages for PulseWidth

     - if the message hasn't been processed, then attempt to
  """

  @doc since: "0.0.21"
  def handle_message(%{processed: false, type: "pwm"} = msg_in) do
    # the with begins with processing the message through DB.Device.upsert/1
    with %{device: device} = msg <- Device.upsert(msg_in),
         # was the upset a success?
         {:ok, %Device{}} <- device,
         # technically the message has been processed at this point
         msg <- Map.put(msg, :processed, true),
         # PulseWidth does not write any data to the timeseries database
         # (unlike Sensor, Remote) so simulate the write_rc success
         # now send the augmented message to the timeseries database
         msg <- Map.put(msg, :write_rc, {:processed, :ok}) do
      msg
    else
      # if there was an error, add fault: <device_fault> to the message and
      # the corresponding <device_fault>: <error> to signal to downstream
      # functions there was an issue
      error ->
        Map.merge(msg_in, %{
          processed: true,
          fault: :pwm_fault,
          pwm_fault: error
        })
    end
  end

  # if the primary handle_message does not match then simply return the msg
  # since it wasn't for switch and/or has already been processed in the
  # pipeline
  def handle_message(%{} = msg_in), do: msg_in

  @doc delegate_to: {Notify, :notify_as_needed, 1}
  @doc since: "0.0.26"
  defdelegate notify_as_needed(msg), to: Notify

  @doc delegate_to: {Server, :notify_register, 1}
  @doc since: "0.0.26"
  defdelegate notify_register(name), to: Notify

  @doc delegate_to: {Server, :notify_map, 0}
  @doc since: "0.0.27"
  defdelegate notify_map, to: Notify

  @doc """
    Retrieve a list of alias names
  """
  @doc since: "0.0.22"
  defdelegate names, to: Alias, as: :names

  @doc """
    Retrieve a list of PulseWidth alias names that begin with a pattern
  """

  @doc since: "0.0.25"
  defdelegate names_begin_with(pattern), to: Alias

  @doc """
    Set a PulseWidth Alias to minimum duty
  """
  @doc since: "0.0.25"
  defdelegate off(name_or_id), to: Alias

  @doc """
    Set a PulseWidth Alias to maximum duty
  """
  @doc since: "0.0.25"
  defdelegate on(name_or_id), to: Alias

  @doc delegate_to: {Notify, :state, 0}
  @doc since: "0.0.26"
  defdelegate state, to: Notify

  @doc """
    Send a random command to a PulseWidth found by name or actual struct

    PulseWidth.basic(name, basic: %{})
  """
  @doc since: "0.0.22"
  def random(name_id_pwm, cmd_map, opts \\ []) do
    Alias.cmd_direct(name_id_pwm, cmd_map, opts)
  end

  @doc """
  Create and send a random command to a device via cli prompts
  """
  @doc since: "0.0.27"
  defdelegate random_from_cli(name_or_id), to: Example

  @doc delegate_to: {Alias, :rename, 2}
  @doc since: "0.0.27"
  defdelegate rename(name_or_id, new_name), to: Alias

  @doc delegate_to: {Notify, :restart, 1}
  @doc since: "0.0.27"
  defdelegate restart(opts \\ []), to: Notify
end
