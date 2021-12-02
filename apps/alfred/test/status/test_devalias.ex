defmodule Alfred.Test.Datapoint do
  alias __MODULE__

  defstruct temp_c: nil, temp_f: nil, relhum: nil, reading_at: nil

  def new(opts_all) when is_list(opts_all), do: Enum.into(opts_all, %{}) |> new()

  def new(%{datapoints: opts} = opts_all) do
    opts
    |> Keyword.put_new(:temp_c, 27.5)
    |> Keyword.put_new(:temp_f, 81.5)
    |> Keyword.put_new(:relhum, 55.5)
    |> Keyword.put_new(:reading_at, opts[:reading_at] || opts_all[:seen_at])
    |> then(fn fields -> [struct(Datapoint, fields)] end)
  end

  def new(_), do: nil
end

defmodule Alfred.Test.Device do
  alias __MODULE__

  defstruct mutable: false, last_seen_at: nil

  def new(opts_all) when is_list(opts_all), do: Enum.into(opts_all, %{}) |> new()

  def new(%{device: opts} = opts_all) do
    opts
    |> Keyword.put_new(:last_seen_at, opts[:last_seen_at] || opts_all[:seen_at])
    |> then(fn fields -> struct(Device, fields) end)
  end

  def new(_), do: nil
end

defmodule Alfred.Test.Command do
  alias __MODULE__

  defstruct acked: false, acked_at: nil, cmd: nil, orphaned: false, sent_at: nil

  def new(opts_all) when is_list(opts_all), do: Enum.into(opts_all, %{}) |> new()

  def new(%{cmds: opts} = opts_all) do
    opts
    |> Keyword.put_new(:acked, true)
    |> Keyword.put_new(:sent_at, opts[:sent_at] || opts_all[:seen_at])
    |> Keyword.put_new(:acked_at, Timex.now())
    |> Keyword.put_new(:cmd, "on")
    |> Keyword.put_new(:orphaned, false)
    |> then(fn fields -> struct(Command, fields) end)
  end

  def new(_), do: nil
end

defmodule Alfred.Test.DevAlias do
  alias __MODULE__
  alias Alfred.Test.{Command, Datapoint, Device}

  defstruct name: nil, cmds: nil, datapoints: nil, device: nil, ttl_ms: 33_333, updated_at: nil

  def new(opts) do
    Enum.into(opts, [])
    |> Keyword.put_new(:seen_at, Timex.now())
    |> then(fn opts -> Keyword.put_new(opts, :name, Alfred.NamesAid.unique("devalias")) end)
    |> then(fn opts -> Keyword.put_new(opts, :reading_at, opts[:seen_at]) end)
    |> then(fn opts -> Keyword.put_new(opts, :updated_at, opts[:seen_at]) end)
    |> then(fn opts -> Keyword.put(opts, :cmds, Command.new(opts)) end)
    |> then(fn opts -> Keyword.put(opts, :device, Device.new(opts)) end)
    |> then(fn opts -> Keyword.put(opts, :datapoints, Datapoint.new(opts)) end)
    |> then(fn fields -> struct(DevAlias, fields) end)
  end
end
