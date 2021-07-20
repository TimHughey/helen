defmodule Alfred.ExecCmd do
  alias __MODULE__, as: Cmd

  defstruct name: "default",
            cmd: "unknown",
            inserted_cmd: nil,
            cmd_params: %{},
            cmd_opts: [ack: :host, force: false, notify_when_released: false],
            pub_opts: [],
            instruct: nil,
            valid?: false,
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
          valid?: boolean(),
          invalid_reason: nil | String.t()
        }

  def valid(%Cmd{} = ec), do: %Cmd{ec | valid?: true}
  def valid?(%Cmd{} = ec), do: ec.valid?

  def validate(%Cmd{} = ec) do
    case ec do
      %Cmd{cmd: c} when c in ["on", "off"] -> %Cmd{ec | valid?: true}
      %Cmd{cmd: c, cmd_params: %{type: t}} when is_binary(c) and is_binary(t) -> %Cmd{ec | valid?: true}
      %Cmd{cmd: c} when is_binary(c) -> %Cmd{ec | invalid_reason: "custom cmds must include type"}
      _ -> %Cmd{ec | invalid_reason: "cmd must be a binary"}
    end
  end
end
