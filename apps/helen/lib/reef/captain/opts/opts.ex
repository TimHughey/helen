defmodule Reef.Captain.Opts do
  @moduledoc false

  @defaults_file Path.join([__DIR__, "defaults.txt"])
  @defaults_new_file Path.join([__DIR__, "defaults_new.txt"])
  @external_resource @defaults_file
  @external_resource @defaults_new_file
  @defaults_txt File.read!(@defaults_file)
  @defaults_new_txt File.read!(@defaults_new_file)

  def default_opts, do: @defaults_txt
  def default_new_opts, do: @defaults_new_txt

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
