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

  @doc since: "0.2.7"
  @add_accepted [:echo, :force, :notify_when_released]
  def add(%ExecCmd{} = ec, opts) when is_list(opts) do
    for {key, val} when is_atom(key) <- opts, reduce: ec do
      ec_acc ->
        case {key, val} do
          {:cmd, cmd} -> struct(ec_acc, cmd: cmd)
          {:name, name} -> struct(ec_acc, name: name)
          {:notify, true} -> add_cmd_opt(ec_acc, :notify_when_released)
          {key, true} when key in @add_accepted -> add_cmd_opt(ec_acc, key)
          _ -> ec_acc
        end
    end
    |> validate()
  end

  @doc """
  Add a generic `key: true` to cmd_opts
  """
  @doc since: "0.2.6"
  def add_cmd_opt(%ExecCmd{} = ec, key) when is_atom(key) do
    %ExecCmd{ec | cmd_opts: Keyword.put(ec.cmd_opts, key, true)}
  end

  @doc """
  Set `force: true` in command opts
  """
  @doc since: "0.2.6"
  def add_force(%ExecCmd{} = ec), do: add_cmd_opt(ec, :force)

  @doc """
  Set name for `ExecCmd`
  """
  @doc since: "0.2.6"
  def add_name(%ExecCmd{} = ec, name, opts \\ []) when is_binary(name) and is_list(opts) do
    struct(ec, name: name) |> add(opts)
  end

  @doc """
  Set `notify_when_released: true` in command opts
  """
  @doc since: "0.2.6"
  def add_notify(%ExecCmd{} = ec), do: add_cmd_opt(ec, :notify_when_released)

  def add_type(%ExecCmd{cmd_params: params} = ec, type) when is_binary(type) do
    struct(ec, params: Map.put(params, :type, type))
  end

  @doc """
  Merge `cmd_opts` into existing command opts
  """
  @doc since: "0.2.6"
  def merge_cmd_opts(%ExecCmd{cmd_opts: cmd_opts} = ec, opts) do
    %ExecCmd{ec | cmd_opts: Keyword.merge(cmd_opts, opts)}
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
