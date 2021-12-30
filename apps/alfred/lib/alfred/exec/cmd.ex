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
  @ack_types [:immediate, :host]
  @add_accepted [:ack, :echo, :force, :notify, :notify_when_released]
  def add(%ExecCmd{} = ec, opts) when is_list(opts) do
    for {key, val} when is_atom(key) <- opts, reduce: ec do
      ec_acc ->
        case {key, val} do
          {:ack, x} when x in @ack_types -> add_ack(ec, x)
          {:cmd, x} -> struct(ec_acc, cmd: x)
          {:name, x} when is_binary(x) -> struct(ec_acc, name: x)
          {:notify, true} -> add_cmd_opt(ec_acc, :notify_when_released)
          {key, true} when key in @add_accepted -> add_cmd_opt(ec_acc, key)
          _ -> ec_acc
        end
    end
    |> validate()
  end

  def add_ack(%ExecCmd{} = ec, type) when type in @ack_types do
    struct(ec, cmd_opts: Keyword.put(ec.cmd_opts, :ack, type))
  end

  @doc """
  Add a generic `key: true` to cmd_opts
  """
  @doc since: "0.2.6"
  def add_cmd_opt(%ExecCmd{} = ec, key) when is_atom(key) do
    struct(ec, cmd_opts: Keyword.put(ec.cmd_opts, key, true))
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

  @doc since: "0.2.12"
  def from_args(args) when is_list(args) or is_tuple(args) do
    Alfred.ExecCmd.Args.auto(args)
    |> new()
    |> validate()
  end

  @doc since: "0.2.12"
  def cmd_args, do: [:cmd, :cmd_defaults, :cmd_opts, :cmd_params, :name, :pub_opts]

  @doc """
  Merge `cmd_opts` into existing command opts
  """
  @doc since: "0.2.6"
  def merge_cmd_opts(%ExecCmd{cmd_opts: cmd_opts} = ec, opts) do
    struct(ec, cmd_opts: Keyword.merge(cmd_opts, opts))
  end

  @new_keys [:name, :cmd, :cmd_params, :cmd_opts, :pub_opts]
  def new(opts) when is_list(opts) do
    {base_opts, opts_rest} = Keyword.split(opts, @new_keys)

    struct(ExecCmd, base_opts) |> add(opts_rest)
  end

  @doc """
  Adjust the cmd params for an existing `ExecCmd`
  """
  @doc since: "0.2.11"
  def params_adjust(%ExecCmd{} = ec, params) when is_list(params) do
    adjusted = Map.merge(ec.cmd_params, Enum.into(params, %{}))

    struct(ec, cmd: version_cmd(ec.cmd), cmd_params: adjusted)
    |> validate()
  end

  @doc since: "0.2.12"
  def to_args(%ExecCmd{} = ec, as_tuple \\ false) do
    args = Map.take(ec, cmd_args()) |> Enum.into([])

    (as_tuple && {args, ec}) || args
  end

  @doc since: "0.2.12"
  defdelegate version_cmd(cmd_or_args), to: Alfred.ExecCmd.Args

  @doc """
  Validate the `cmd`
  """

  @doc since: "0.2.6"
  def validate(%ExecCmd{cmd_params: params} = ec) when is_list(params) do
    struct(ec, cmd_params: Enum.into(params, %{})) |> validate()
  end

  def validate(%ExecCmd{cmd: cmd} = ec) when is_atom(cmd) do
    struct(ec, cmd: Atom.to_string(cmd)) |> validate()
  end

  def validate(%ExecCmd{} = ec) do
    case ec do
      %{name: "default"} -> invalid(ec, "name is not set")
      %{name: name} when not is_binary(name) -> invalid(ec, "name must be a binary")
      %{cmd: "unknown"} -> invalid(ec, "cmd is not set")
      _ -> valid(ec)
    end
  end

  ##
  ## Private
  ##

  # @cmd_vers_regex ~r/(?: v(?<version>\d{3}$))|(?<cmd>[[:print:]]+)/

  defp invalid(%ExecCmd{} = ec, reason), do: struct(ec, valid: :no, invalid_reason: reason)
  defp valid(%ExecCmd{} = ec), do: struct(ec, valid: :yes)
end
