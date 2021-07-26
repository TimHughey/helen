defmodule Eva.State do
  require Logger

  alias __MODULE__
  alias Eva.{Equipment, Follow, InRange, Opts, TimedCmd, Variant}

  defstruct opts: nil, variant: nil, mode: :starting, started_at: nil, seen_at: nil

  @type server_mode() :: :starting | :finding_names | :ready | :standby
  @type t :: %__MODULE__{
          opts: %Opts{},
          variant: InRange.t() | Follow.t() | TimedCmd.t(),
          mode: server_mode(),
          started_at: DateTime.t(),
          seen_at: DateTime.t()
        }

  def just_saw(%State{} = s) do
    Alfred.JustSaw.new(s.opts.server.name, :mutable, %{name: s.variant.name, ttl_ms: 60_000})
    |> Alfred.just_saw_cast()

    %State{s | seen_at: DateTime.utc_now()}
  end

  def load_config(%State{opts: %Opts{} = opts} = s) do
    toml_rc = opts.toml_file |> Toml.decode_file(keys: :atoms)

    %State{s | variant: Variant.Factory.new(toml_rc, opts), opts: Opts.append_cfg(toml_rc, s.opts)}
  end

  def new(%Opts{} = opts) do
    s = %State{opts: opts, started_at: DateTime.utc_now()}

    if s.opts |> Opts.valid?() do
      s
    else
      Logger.error("invalid opts: #{inspect(s.opts, pretty: true)}")
      {:stop, :invalid_opts}
    end
  end

  def mode(%State{} = s, mode) do
    case mode do
      :resume -> %State{s | mode: :ready}
      x -> %State{s | mode: x}
    end
  end

  def update(%{equipment: %Equipment{}} = v, %State{} = s), do: %State{s | variant: v}

  def update_variant(v, %State{} = s) do
    %State{s | variant: v}
  end
end
