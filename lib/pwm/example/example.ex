defmodule PulseWidth.Command.Example do
  @moduledoc """
  Example coomand payloads for PulseWidth devices.
  """

  alias PulseWidth.DB.{Alias, Command, Device}

  def cmd(type, opts) when is_atom(type) do
    import Ecto.Query, only: [from: 2]
    import Repo, only: [all: 1, preload: 2]

    opts = [opts] |> List.flatten()

    one_cmd = from(x in Command, order_by: [desc: x.sent_at], limit: 1)

    %Command{device: device} =
      one_cmd |> all() |> preload([:device, :alias]) |> hd()

    device = Repo.preload(device, [:_alias_, cmds: one_cmd])

    from_device(device, type, opts)
  end

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

    Creates the PulseWidth Command Example using %Device{} based on type

    NOTE:  This function is exposed publicly although, for a quick example,
           use cmd_example/2

      ### Supported Types
        [:duty, :basic, :random]

      ### Examples
        iex> PulseWidth.cmd_example_cmd(:random, %Device{})
  """

  @doc since: "0.0.22"
  def from_device(%Device{} = pwm, type, opts) when is_atom(type) do
    alias PulseWidth.Payload.{Basic, Duty, Random}

    payload =
      case type do
        :random -> Random.example(pwm)
        :basic -> Basic.example(pwm)
        :duty -> Duty.example(pwm)
        true -> %{}
      end

    case opts do
      [:cmd_map] -> get_in(payload, [:cmd]) |> Map.drop([:type])
      _any -> payload
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
end
