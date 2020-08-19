defmodule Reef.FirstMate.Opts do
  @moduledoc false

  @defaults_file Path.join([__DIR__, "defaults.txt"])
  @external_resource @defaults_file
  @defaults_txt File.read!(@defaults_file)

  def default_opts, do: @defaults_txt

  def parsed(raw \\ nil) do
    alias Helen.Config.Parser

    if is_nil(raw) or raw === "" do
      default_opts() |> Parser.parse()
    else
      raw |> Parser.parse()
    end
    |> get_in([:config])
  end
end
