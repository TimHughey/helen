defmodule Alfred.ExecCmd do
  require Logger

  alias __MODULE__

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

  def add_notify(%ExecCmd{cmd_opts: opts} = ec) do
    struct(ec, cmd_opts: Keyword.put(opts, :notify_when_released, true))
  end

  def add_type(%ExecCmd{cmd_params: params} = ec, type) when is_binary(type) do
    struct(ec, params: Map.put(params, :type, type))
  end

  @allowed_keys [:name, :cmd, :cmd_params, :cmd_opts, :pub_opts]
  def new(opts) when is_list(opts) do
    {allowed, opts_rest} = Keyword.split(opts, @allowed_keys)

    if opts_rest != [], do: Logger.warn("unrecognized opts: #{inspect(opts_rest)}")

    struct(ExecCmd, allowed) |> validate()
  end

  def validate(%ExecCmd{} = ec) do
    case ec do
      %ExecCmd{cmd: c} when c in ["on", "off"] -> valid(ec)
      %ExecCmd{cmd_params: x} when is_list(x) -> struct(ec, cmd_params: Enum.into(x, %{})) |> validate()
      %ExecCmd{cmd: c, cmd_params: %{type: t}} when is_binary(c) and is_binary(t) -> valid(ec)
      %ExecCmd{cmd: c} when is_binary(c) -> invalid(ec, "custom cmds must include type")
      _ -> invalid(ec, "cmd must be a binary")
    end
  end

  ##
  ## Private
  ##

  defp invalid(%ExecCmd{} = ec, reason), do: %ExecCmd{ec | valid: :no, invalid_reason: reason}
  defp valid(%ExecCmd{} = ec), do: %ExecCmd{ec | valid: :yes}
end
