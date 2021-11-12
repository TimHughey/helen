defmodule Alfred.JustSaw do
  alias __MODULE__

  defmodule Alias do
    defstruct name: nil, ttl_ms: nil, valid?: false

    @type t :: %__MODULE__{
            name: String.t(),
            ttl_ms: pos_integer(),
            valid?: boolean()
          }

    # (1 of 2) handle creating multiple Aliases (list of lists or maps)
    def new([first | _] = aliases) when is_list(first) or is_map(first) do
      for x <- aliases do
        new(x)
      end
      |> List.flatten()
    end

    def new(x) when is_list(x) or is_map(x), do: [struct(Alias, x) |> validate()]

    def new(_x), do: [%Alias{}]

    defp validate(%Alias{name: name, ttl_ms: ttl_ms} = dev_alias) do
      with name when is_binary(name) <- name,
           ttl_ms when is_integer(ttl_ms) and ttl_ms > 0 <- ttl_ms do
        %Alias{dev_alias | valid?: true}
      else
        _ -> dev_alias
      end
    end
  end

  defstruct mutable?: false,
            callback_mod: Alfred.NoCallback,
            server_name: Alfred.NoServer,
            seen_list: [],
            valid?: false

  @type t :: %__MODULE__{
          mutable?: boolean(),
          callback_mod: module(),
          server_name: atom(),
          seen_list: [Alias.t(), ...],
          valid?: boolean()
        }

  @want_keys [:mutable?, :callback_mod, :server_name, :seen]
  def new(args) when is_list(args) or is_map(args) do
    clean_args = Enum.into(args, %{}) |> Map.take(@want_keys)

    seen = clean_args[:seen] || []

    %JustSaw{struct(JustSaw, clean_args) | seen_list: Alias.new(seen)} |> validate()
  end

  def new(callback_mod, type, %{name: name, ttl_ms: ttl_ms}) when type in [:mutable, :immutable] do
    %JustSaw{
      mutable?: type == :mutable,
      callback_mod: callback_mod,
      seen_list: [%Alias{name: name, ttl_ms: ttl_ms}]
    }
  end

  def new(callback_mod, mutable?, details) when is_boolean(mutable?) and is_map(details) do
    new(callback_mod, if(mutable?, do: :mutable, else: :immutable), details)
  end

  def validate(%JustSaw{callback_mod: cb, server_name: sn} = js)
      when cb == Alfred.NoCallback and sn == Alfred.NoServer do
    %JustSaw{js | valid?: false}
  end

  def validate(%JustSaw{} = js), do: %JustSaw{js | valid?: true}
end
