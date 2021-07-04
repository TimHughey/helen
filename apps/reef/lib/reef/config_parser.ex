defmodule NewReef.Action do
  alias __MODULE__

  defstruct cmd: nil, for_ms: nil, for_iso: nil, nowait: false, then_cmd: nil, worker_name: nil

  @type t :: %__MODULE__{
          cmd: atom(),
          for_ms: pos_integer() | nil | {:error, term()},
          for_iso: String.t() | nil,
          nowait: boolean(),
          then_cmd: atom() | nil,
          worker_name: atom()
        }

  def new(details) do
    for_iso = details[:for]
    for_ms = for_iso |> EasyTime.iso8601_duration_to_ms()
    nowait = if is_nil(details[:nowait]), do: false, else: details[:nowait]

    %Action{
      cmd: details[:cmd],
      for_ms: for_ms,
      for_iso: for_iso,
      nowait: nowait,
      then_cmd: details[:then],
      worker_name: details[:worker_name]
    }
  end
end

defmodule NewReef.Step do
  alias __MODULE__
  alias NewReef.Action

  defstruct name: nil, actions: [], for_ms: nil, for_iso: nil

  @type t :: %__MODULE__{
          name: String.t(),
          actions: [term(), ...],
          for_ms: pos_integer() | nil | {:error, term()},
          for_iso: String.t() | nil
        }

  def new(details) do
    for_iso = details[:for]
    for_ms = for_iso |> EasyTime.iso8601_duration_to_ms()
    step = %Step{name: details[:name], for_ms: for_ms, for_iso: for_iso}

    for action_details <- details[:actions], reduce: step do
      %Step{actions: acc} = step ->
        action = Action.new(action_details)
        # NOTE the ordering of the actions must be preserved, using less efficient append to list
        %Step{step | actions: acc ++ [action]}
    end
  end
end

defmodule NewReef.Mode do
  alias __MODULE__

  defstruct name: nil, sequence: [], next_mode: nil, steps: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          sequence: [atom(), ...] | [],
          next_mode: atom(),
          steps: map()
        }

  def make_steps(details) do
    alias NewReef.Step

    steps = Keyword.take(details, [:step])

    for {:step, step_info} <- steps, into: %{} do
      step = Step.new(step_info)

      {step.name, step}
    end
  end

  def new(name, details) do
    %Mode{
      name: name,
      next_mode: details[:next_mode],
      sequence: details[:sequence],
      steps: Mode.make_steps(details)
    }
  end
end

defmodule NewReef.Config do
  @moduledoc false

  require Logger
  alias __MODULE__

  defstruct config_vsn: nil,
            description: nil,
            first_mode: nil,
            syntax_vsn: nil,
            timeout: nil,
            timezone: nil,
            worker_name: nil,
            workers: %{},
            modes: %{},
            valid?: true,
            invalid_reason: nil

  @type t :: %__MODULE__{
          config_vsn: String.t() | nil,
          description: String.t() | nil,
          first_mode: atom() | nil,
          syntax_vsn: String.t() | nil,
          timeout: String.t() | nil,
          timezone: String.t() | nil,
          worker_name: atom() | nil,
          workers: map(),
          modes: %{optional(atom()) => Mode.t()},
          valid?: boolean(),
          invalid_reason: any()
        }

  def make_modes(details) do
    alias NewReef.Mode

    modes = Keyword.take(details, [:mode])

    for {:mode, %{name: name, details: details}} <- modes, into: %{} do
      {name, Mode.new(name, details)}
    end
  end

  def parse(path, filename) do
    with {:ok, raw} <- [path, filename] |> Path.join() |> File.read(),
         {:ok, tokens, _} <- raw |> to_charlist() |> :reef_lexer.string(),
         {:ok, parsed} <- tokens |> :reef_parser.parse() do
      base = parsed[:base]

      cfg = %Config{
        config_vsn: base[:config_vsn],
        description: base[:description],
        first_mode: base[:first_mode],
        syntax_vsn: base[:syntax_vsn],
        timeout: base[:timeout],
        timezone: base[:timezone],
        worker_name: base[:worker_name],
        workers: parsed[:workers] |> Enum.into(%{}),
        modes: make_modes(parsed)
      }

      Logger.info("\n#{inspect(cfg, pretty: true)}")
      # Logger.info("\n#{inspect(parsed, pretty: true)}")
      cfg
    else
      error -> %Config{valid?: false, invalid_reason: error}
    end
  end

  def collapse(parsed, collection) when collection in [:modes, :commands] do
    import String, only: [to_atom: 1, trim_trailing: 2]

    key = to_string(collection) |> trim_trailing("s") |> to_atom()

    {items, rest} = Keyword.split(parsed, [key])

    for {^key, details} when is_map(details) <- items,
        reduce: Keyword.put_new(rest, collection, %{}) do
      parsed ->
        case details do
          %{cmd: cmd} ->
            put_in(parsed, [collection, cmd], details)

          %{name: name} ->
            put_in(parsed, [collection, name], details)
        end
    end
  end

  def collapse(parsed, :mode_steps) do
    modes = get_in(parsed, [:modes])

    for {mode_name, %{details: mode_details}} <- modes, reduce: parsed do
      parsed ->
        # mode details is a keyword list with key :details and one or more
        # :step keys
        {steps, mode_meta} = Keyword.split(mode_details, [:step])

        # populate the mode with only the meta data, the following for will
        # handle the steps
        parsed = put_in(parsed, [{:mode, mode_name}], mode_meta)
        # put_in(parsed, [:modes, mode_name, :details], mode_meta)
        # |> put_in([:modes, mode_name, :details, :steps], %{})

        # reduce parsed with the transformation of the list of steps into a map
        for {:step, %{name: step_name} = step_details} <- steps,
            reduce: parsed do
          parsed ->
            put_in(
              parsed,
              # [:modes, mode_name, :details, :steps, step_name],
              # [:modes, mode_name, {:step, step_name}],
              [{:mode, mode_name}, {:step, step_name}],
              step_details
            )
        end
    end
  end

  # def required_modes do
  #   [
  #     all_stop: %{
  #       details: [
  #         next_mode: :hold,
  #         sequence: [:all_stop],
  #         steps: %{
  #           all_stop: %{
  #             actions: [%{cmd: :off, worker_name: :all}]
  #           }
  #         }
  #       ],
  #       name: :all_stop
  #     }
  #   ]
  # end
end
