defmodule Helen.Worker.Config.DB.Line do
  @moduledoc false

  use Ecto.Schema

  alias Helen.Worker.Config.DB.Config
  alias Helen.Worker.Config.DB.Line, as: Schema

  schema "worker_config_line" do
    field(:line, :string, default: " ")
    field(:num, :integer)

    belongs_to(:config, Config, foreign_key: :worker_config_id)
  end

  def as_binary(lines) do
    for %Schema{line: line} <- lines, reduce: "" do
      "" -> line
      x -> Enum.join([x, "\n", line])
    end
  end

  @doc false
  def changeset(cfg, params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_format: 3,
        validate_required: 2
      ]

    cfg
    |> cast(Enum.into(params, %{}), [:line, :num])
    |> validate_required([:num])
    |> validate_format(:line, ~r/[[:ascii:]]+/)
  end

  def insert(%Config{} = cfg, raw) when is_binary(raw) do
    import Repo, only: [checkout: 1]

    lines = split_raw(raw)

    checkout(fn -> insert(cfg, lines) end)
  end

  def insert(%Config{} = cfg, lines) when is_list(lines) do
    import Ecto, only: [build_assoc: 2]

    for line_of_text <- lines, reduce: %{db: :ok, count: 0} do
      # first reduction or previous reducion was a success
      %{db: :ok, count: count} ->
        count = count + 1
        line = build_assoc(cfg, :lines)

        line_of_text = if line_of_text == "", do: " ", else: line_of_text

        cs = changeset(line, line: line_of_text, num: count)

        with {cs, true} <- {cs, cs.valid?()},
             {:ok, %Schema{id: _id}} <- Repo.insert(cs) do
          %{db: :ok, count: count}
        else
          {cs, false} ->
            %{db: {:invalid_changes, cs}, count: count}

          {:error, rc} ->
            %{db: {:error, rc}, count: count}

          error ->
            %{db: {:error, error}, count: count}
        end

      # previous reductin failed
      acc ->
        acc
    end
  end

  def preload(cfg_list) when is_list(cfg_list) do
    for %Config{} = cfg <- cfg_list, do: preload(cfg)
  end

  def preload(%Config{} = cfg) do
    import Ecto.Query, only: [from: 2]

    Repo.preload(cfg, lines: from(line in Schema, order_by: line.num))
  end

  def split_raw(raw) do
    case Regex.split(~r/[\n|\r|\r\n]/, raw) do
      # blank lines are converted to have a single space
      "" -> " "
      x -> x
    end
  end
end
