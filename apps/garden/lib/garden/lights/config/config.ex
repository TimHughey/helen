defmodule Lights.Config do
  @moduledoc false

  @suninfo_wait_ms Application.compile_env!(:garden, [Lights, :suninfo_wait_ms]) || 1000

  # (1 of 2) entry for ensuring suninfo is available
  def ensure_suninfo(cfg_file) do
    ensure_suninfo(cfg_file, 0)
  end

  # (2 of 2) accumulator to only wait for 1000ms
  def ensure_suninfo(cfg_file, acc) do
    import Agnus, only: [sun_info: 1]

    # only wait when the first check failed
    if acc > 0, do: Process.sleep(1)

    failed_msg = {:suninfo, "suninfo not available"}

    if acc < @suninfo_wait_ms do
      case sun_info(:sunrise) do
        %DateTime{} -> cfg_file
        false -> ensure_suninfo(cfg_file, acc + 1)
        [] -> failed_msg
      end
    else
      failed_msg
    end
  end

  def file_info(cfg_file) do
    import File, only: [stat: 2]
    alias File.Stat

    case stat(cfg_file, time: :posix) do
      {:ok, %Stat{} = stat} -> stat
      e -> e
    end
  end

  # extracts :server from the cfg and merge it into state :opts
  # then store the pruned cfg in the state
  def merge_opts(%{opts: opts} = s, cfg) do
    server = get_in(cfg, [:server]) || %{}
    opts = Map.merge(opts, server)
    cfg = Map.drop(cfg, [:server])

    put_in(s, [:opts], opts) |> put_in([:cfg], cfg)
  end

  # (1 of 4) attempt to parse the specified file at binary path
  def parse(cfg_file) when is_binary(cfg_file) do
    case ensure_suninfo(cfg_file) do
      x when is_tuple(x) -> x
      x -> parse(x, file_info(cfg_file))
    end
  end

  # (2 of 4) whoops, the cfg_file path isn't a binary
  def parse(cfg_file), do: {:bad_cfg_file, cfg_file}

  # (3 of 4) perform the actual decode we have file stat info
  def parse(cfg_file, %{size: _} = fstat) do
    import Lights.Config.Transforms, only: [all: 0]
    import Toml, only: [decode_file: 2]

    case decode_file(cfg_file, keys: :atoms, transforms: all()) do
      {:ok, %{} = x} when map_size(x) > 0 -> {:ok, put_in(x, [:fstat], fstat)}
      x -> x
    end
  end

  # (4 of 4) file stat failed
  def parse(_cf, e) when is_tuple(e), do: e

  # (1 of 3) state contains :invalid, need reload
  def reload_if_needed(%{invalid: _} = s) do
    Map.drop(s, [:invalid]) |> reload_if_needed()
  end

  # (2 of 3) has the on disk configurtion file changed?
  def reload_if_needed(%{args: args, cfg: %{fstat: fstat}} = s) do
    import Map, only: [drop: 2, equal?: 2]
    alias File.Stat

    cfg_file = get_in(args, [:cfg_file])
    latest_fstat = file_info(cfg_file)

    # if latest fstat != current false then drop cfg from state and
    # call reload_if_needed/1 to detect missing config
    case latest_fstat do
      %Stat{} = x ->
        if equal?(fstat, x), do: s, else: drop(s, [:cfg]) |> reload_if_needed()

      {:error, error} ->
        put_error(s, error, cfg_file) |> reload_if_needed()
    end
  end

  # (3 of 3) cfg key missing or empty, reload is needed
  def reload_if_needed(%{args: args, opts: _} = s) do
    file = get_in(args, [:cfg_file]) || "missing_config"

    case parse(file) do
      {:ok, cfg} when is_map(cfg) -> merge_opts(s, cfg)
      {:error, e} -> put_error(s, e, file)
      {:bad_cfg_file = e, cfg_file} -> put_error(s, e, cfg_file)
    end
  end

  # (1 of 5) insert the error msg into the :invalid list
  def put_error(s, :invalid, msg) do
    import List, only: [flatten: 1]
    import Map, only: [merge: 2]

    invalids = get_in(s, [:invalid]) || []

    merge(s, %{invalid: [invalids, msg] |> flatten(), cfg: %{}})
  end

  # (2 of 5) the cfg file was not a binary!
  def put_error(s, :bad_cfg_file, cfg_file) do
    msg = "cfg file is not a binary: #{inspect(cfg_file)}"
    put_error(s, :invalid, msg)
  end

  # (3 of 5) make a friendly not found message when the cfg file doesn't exist
  def put_error(s, :enoent, cfg_file) when is_binary(cfg_file) do
    msg = "cfg file not found: #{cfg_file}"
    put_error(s, :invalid, msg)
  end

  def put_error(s, {:invalid_toml, msg}, cfg_file) when is_binary(msg) do
    msg = "cfg file: #{cfg_file} parse failed: #{msg}"
    put_error(s, :invalid, msg)
  end

  # (4 of 5) catch all when error is a binary
  def put_error(s, error, _cfg_file) when is_binary(error) do
    put_error(s, :invalid, error)
  end

  # (4 of 5) catch all when error is a binary
  # def put_error(s, error, _cfg_file)  do
  #   put_error(s, :invalid, error)
  # end
end
