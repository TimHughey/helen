defmodule Alfred.ExecCmd do
  alias __MODULE__, as: Cmd

  defstruct name: "default",
            cmd: "unknown",
            inserted_cmd: nil,
            cmd_params: %{},
            cmd_opts: [ack: :host, force: false, notify_when_released: false],
            pub_opts: [],
            instruct: nil,
            valid: :unchecked,
            invalid_reason: nil

  @type cmd() :: String.t()
  @type ack_method() :: :immediate | :host
  @type cmd_opts() :: [
          force: boolean(),
          notify_when_released: boolean(),
          track_timeout_ms: pos_integer(),
          ttl_ms: pos_integer(),
          ack: ack_method()
        ]
  @type cmd_params() :: %{:type => String.t(), optional(atom()) => any()}
  @type pub_opts() :: [qos: 0..2]

  @type t :: %__MODULE__{
          name: String.t(),
          cmd: cmd(),
          inserted_cmd: Ecto.Schema.t(),
          cmd_params: cmd_params(),
          cmd_opts: cmd_opts(),
          pub_opts: pub_opts(),
          instruct: nil | struct(),
          valid: :unchecked | :yes | :no,
          invalid_reason: nil | String.t()
        }

  # def valid(%Cmd{} = ec), do: %Cmd{ec | valid?: true}
  # def valid?(%Cmd{} = ec), do: ec.valid?

  def validate(%Cmd{} = ec) do
    case ec do
      %Cmd{cmd: c} when c in ["on", "off"] -> valid(ec)
      %Cmd{cmd: c, cmd_params: %{type: t}} when is_binary(c) and is_binary(t) -> valid(ec)
      %Cmd{cmd: c} when is_binary(c) -> invalid(ec, "custom cmds must include type")
      _ -> invalid(ec, "cmd must be a binary")
    end
  end

  ##
  ## Private
  ##

  defp invalid(%Cmd{} = ec, reason) do
    %Cmd{ec | valid: :no, invalid_reason: reason}
  end

  defp valid(%Cmd{} = ec), do: %Cmd{ec | valid: :yes}
end
