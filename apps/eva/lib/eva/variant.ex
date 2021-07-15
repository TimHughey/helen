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

  @spec valid?(struct()) :: boolean()
  def valid?(variant)
end

defmodule Eva.Variant.Factory do
  alias Eva.{Follow, Variant}

  def new(toml_rc) do
    case toml_rc do
      {:ok, %{variant: "in range"} = x} -> Variant.InRange.new(x)
      {:ok, %{variant: "follow"} = x} -> Follow.new(x)
      {:error, error} -> Variant.Invalid.new(error)
    end
  end
end

defmodule Eva.Variant.Invalid do
  alias __MODULE__

  defstruct valid?: false, invalid_reason: nil

  @type t :: %__MODULE__{
          valid?: boolean(),
          invalid_reason: any()
        }

  def new(invalid_reason), do: %__MODULE__{valid?: false, invalid_reason: invalid_reason}

  defimpl Eva.Variant do
    def control(%Invalid{} = x, %Alfred.NotifyMemo{}, _mode), do: x
    def current_mode(%Invalid{}), do: :invalid
    def find_devices(%Invalid{} = x), do: x
    def found_all_devs?(%Invalid{}), do: false
    def handle_notify(%Invalid{} = x, %Alfred.NotifyMemo{}, _mode), do: x
    def handle_release(%Invalid{} = x, %Broom.TrackerEntry{}), do: x
    def mode(%Invalid{} = x, _mode), do: x
    def valid?(%Invalid{}), do: false
  end
end
