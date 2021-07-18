defmodule Eva.State do
  require Logger

  alias __MODULE__
  alias Eva.{Follow, Opts}
  alias Eva.Variant

  defstruct opts: nil, variant: nil, mode: :starting, started_at: nil

  @type t :: %__MODULE__{
          opts: %Opts{},
          variant: Variant.InRange.t() | Follow.t() | Variant.Invalid.t(),
          mode: :starting | :ready | :standby,
          started_at: DateTime.t()
        }

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
    %State{s | mode: mode}
  end

  def update_variant(v, %State{} = s), do: %State{s | variant: v}
end
