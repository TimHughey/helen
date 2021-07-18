defprotocol Eva.Variant do
  @type server_mode() :: :starting | :ready | :standby
  @spec control(struct(), Alfred.NotifyMemo.t(), server_mode()) :: struct()
  def control(variant, memo, mode)

  @spec current_mode(struct()) :: atom()
  def current_mode(variant)

  @spec find_devices(struct()) :: struct()
  def find_devices(variant)

  @spec found_all_devs?(struct()) :: boolean()
  def found_all_devs?(variant)

  @spec handle_notify(struct(), Alfred.NotifyMemo.t(), server_mode()) :: struct()
  def handle_notify(variant, memo, mode)

  @spec handle_release(struct(), Broom.TrackerEntry.t()) :: struct()
  def handle_release(variant, tracker_entry)

  @spec mode(struct(), server_mode()) :: struct()
  def mode(variant, mode)

  @spec new(struct(), Eva.Opts.t(), extra_opts :: list()) :: struct()
  def new(variant, eva_opts, extra_opts)

  @spec valid?(struct()) :: boolean()
  def valid?(variant)
end

defmodule Eva.Invalid do
  alias __MODULE__

  defstruct name: "invalid", mod: nil, valid?: false, invalid_reason: nil

  @type t :: %Invalid{
          name: String.t(),
          mod: module(),
          valid?: boolean(),
          invalid_reason: any()
        }
end

defimpl Eva.Variant, for: Eva.Invalid do
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.{Invalid, Opts}

  def control(%Invalid{} = x, %Memo{}, _mode), do: x
  def current_mode(%Invalid{}), do: :invalid
  def find_devices(%Invalid{} = x), do: x
  def found_all_devs?(%Invalid{}), do: false
  def handle_notify(%Invalid{} = x, %Memo{}, _mode), do: x
  def handle_release(%Invalid{} = x, %TrackerEntry{}), do: x
  def mode(%Invalid{} = x, _mode), do: x

  def new(%Invalid{} = x, %Opts{} = opts, extra_opts) do
    %Invalid{x | mod: opts.server.name, valid?: false, invalid_reason: extra_opts[:reason]}
  end

  def valid?(%Invalid{}), do: false
end

defmodule Eva.Variant.Factory do
  alias Eva.{Follow, Invalid, Opts, Setpoint, Variant}

  def new(toml_rc, %Opts{} = opts) do
    case toml_rc do
      {:ok, %{variant: "setpoint"} = x} -> %Setpoint{} |> Setpoint.new(opts, cfg: x)
      {:ok, %{variant: "follow"} = x} -> %Follow{} |> Variant.new(opts, cfg: x)
      {:error, error} -> %Invalid{} |> Variant.new(opts, reason: error)
    end
  end
end
