defmodule PulseWidth do
  @moduledoc """
    The PulseWidth module provides the base of a sensor reading.
  """

  require Logger
  use Timex

  alias PulseWidth.DB.Alias, as: Alias
  alias PulseWidth.DB.Command, as: Command
  alias PulseWidth.DB.Device, as: Device

  def test do
    names() |> hd() |> duty(duty: :rand.uniform(8191))
  end

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

  # @doc """
  #   Send a basic sequence to a PulseWidth found by name or actual struct
  #
  #   PulseWidth.basic(name, basic: %{})
  # """

  # @doc since: "0.0.22"
  # def basic(name_id_pwm, cmd_map, opts \\ [])
  #
  # def basic(%Device{} = pwm, %{name: name} = cmd, opts)
  #     when is_list(opts) do
  #   import TimeSupport, only: [utc_now: 0]
  #   import PulseWidth.Payload.Basic, only: [send_cmd: 4]
  #
  #   # update the PulseWidth
  #   with {:ok, %Device{} = pwm} <- Device.update(pwm, running_cmd: name),
  #        # add the command
  #        {:ok, %Device{} = pwm} <- Device.add_cmd(pwm, utc_now()),
  #        # get the Command inserted
  #        {:cmd, %Command{refid: refid}} <- {:cmd, hd(pwm.cmds)},
  #        # send the command
  #        pub_rc <- send_cmd(pwm, refid, cmd, opts) do
  #     # assemble return value
  #     [basic: [name: name, pub_rc: pub_rc] ++ [opts]]
  #   else
  #     # just pass through any error encountered
  #     error -> {:error, error}
  #   end
  # end
  #
  # def basic(x, %{name: _, basic: %{repeat: _, steps: _}} = cmd, opts)
  #     when is_list(opts) do
  #   with %Device{} = pwm <- Device.find(x) do
  #     basic(pwm, cmd, opts)
  #   else
  #     nil -> {:not_found, x}
  #   end
  # end

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
  Generate an example cmd payload using the first PulseWidth
  known to the system (sorted in ascending order).

  This function embeds documentation in the live system.

    ### Examples
      iex> PulseWidth.cmd_example(type, encode: true)
      Minimized JSON encoded Elixir native representation

      iex> PulseWidth.cmd_example(type, binary: true)
      Minimized JSON encoded binary representation

      iex> PulseWidth.cmd_example(type, bytes: true)
      Byte count of minimized JSON

      iex> PulseWidth.cmd_example(type, pack: true)
      Byte count of MsgPack encoding

      iex> PulseWidth.cmd_example(type, write: true)
      Appends pretty version of JSON encoded Sequence to
       ${HOME}/devel/helen/extra/json-snippets/basic.json

    ### Supported Types
      [:basic, :duty, :random]
  """

  @doc since: "0.0.14"
  def cmd_example(type \\ :random, opts \\ [])
      when is_atom(type) and is_list(opts) do
    name = names() |> hd()

    with %Alias{name: _} = pwm <- alias_find(name),
         cmd <- cmd_example_cmd(type, pwm) do
      cmd |> cmd_example_opts(opts)
    else
      error -> {:error, error}
    end
  end

  @doc """
    Creates the PulseWidth Command Example using %Device{} based on type

    NOTE:  This function is exposed publicly although, for a quick example,
           use cmd_example/2

      ### Supported Types
        [:duty, :basic, :random]

      ### Examples
        iex> PulseWidth.cmd_example_cmd(:random, %Device{})
  """

  @doc since: "0.0.22"
  def cmd_example_cmd(type, %Device{} = pwm) when is_atom(type) do
    alias PulseWidth.Payload.{Basic, Duty, Random}

    case type do
      :random -> Random.example(pwm)
      :basic -> Basic.example(pwm)
      :duty -> Duty.example(pwm)
      true -> %{}
    end
  end

  def cmd_example_file(%{pwm_cmd: cmd}) do
    cond do
      cmd == 0x10 -> "duty.json"
      cmd == 0x11 -> "basic.json"
      cmd == 0x12 -> "random.json"
      true -> "undefined.json"
    end
  end

  def cmd_example_opts(%{} = cmd, opts) do
    import Jason, only: [encode!: 2, encode_to_iodata!: 2]
    import Msgpax, only: [pack!: 1]

    cond do
      Keyword.has_key?(opts, :encode) ->
        Jason.encode!(cmd)

      Keyword.has_key?(opts, :binary) ->
        Jason.encode!(cmd, []) |> IO.puts()

      Keyword.has_key?(opts, :bytes) ->
        encode!(cmd, []) |> IO.puts() |> String.length()

      Keyword.has_key?(opts, :pack) ->
        [pack!(cmd)] |> IO.iodata_length()

      Keyword.has_key?(opts, :write) ->
        out = ["\n", encode_to_iodata!(cmd, pretty: true), "\n"]
        home = System.get_env("HOME")

        name = cmd_example_file(cmd)

        file =
          [
            home,
            "devel",
            "helen",
            "extra",
            "json-snippets",
            name
          ]
          |> Path.join()

        File.write(file, out, [:append])

      true ->
        cmd
    end
  end

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

  defdelegate duty(name, opts \\ []), to: Alias
  defdelegate duty_names_begin_with(patterm, opts \\ []), to: Alias

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
         # Switch does not write any data to the timeseries database
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

  # @doc """
  #   Send a random command to a PulseWidth found by name or actual struct
  #
  #   PulseWidth.basic(name, basic: %{})
  # """
  # @doc since: "0.0.22"
  # def random(name_id_pwm, cmd_map, opts \\ [])
  #
  # def random(%Device{} = pwm, %{name: name} = cmd, opts)
  #     when is_list(opts) do
  #   import TimeSupport, only: [utc_now: 0]
  #   import PulseWidth.Payload.Random, only: [send_cmd: 4]
  #
  #   # update the PulseWidth
  #   with {:ok, %Device{} = pwm} <- Device.update(pwm, running_cmd: name),
  #        # add the command
  #        {:ok, %Device{} = pwm} <- Device.add_cmd(pwm, utc_now()),
  #        # get the Command inserted
  #        {:cmd, %Command{refid: refid}} <- {:cmd, hd(pwm.cmds)},
  #        # send the command
  #        pub_rc <- send_cmd(pwm, refid, cmd, opts) do
  #     # assemble return value
  #     [random: [name: name, pub_rc: pub_rc] ++ [opts]]
  #   else
  #     # just pass through any error encountered
  #     error -> {:error, error}
  #   end
  # end
  #
  # def random(x, %{name: _, random: %{}} = cmd, opts) when is_list(opts) do
  #   with %Device{} = pwm <- Device.find(x) do
  #     random(pwm, cmd, opts)
  #   else
  #     nil -> {:not_found, x}
  #   end
  # end
end
