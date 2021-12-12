defmodule CarolPlaylist.Test do
  use ExUnit.Case, async: true
  use Should

  alias Carol.Playlist
  alias Carol.Playlist.Entry

  @moduletag carol: true, carol_playlist: true

  setup_all do
    {:ok, %{opts_add: []}}
  end

  setup [:opts_add, :program_add, :playlist_add, :dump]

  defmacro assert_entry(entry, id, type) do
    quote location: :keep, bind_quoted: [entry: entry, id: id, type: type] do
      entry
      |> Should.Be.Struct.with_all_key_value(Entry, type: type, id: id)
    end
  end

  describe "Carol.Playlist.active/2" do
    @tag program_add: :live_programs, playlist_add: []
    # @tag dump: [:programs, :playlist]
    test "returns active entry (when present)", ctx do
      ctx.playlist
      |> Playlist.active()
      |> assert_entry("Live", :active)
    end

    @tag program_add: :future_programs, playlist_add: []
    test "returns :none (when not present)", ctx do
      ctx.playlist
      |> Playlist.active()
      |> Should.Be.equal(:none)
    end
  end

  describe "Carol.Playlist.next_first/2" do
    @tag program_add: :live_programs, playlist_add: []
    # @tag dump: [:programs, :playlist]
    test "returns next entry (when present, sorted by :ms)", ctx do
      ctx.playlist
      |> Playlist.next_first()
      |> assert_entry("Future", :next)
    end

    # @tag program_add: :future_programs, playlist_add: []
    # test "returns :none (when not present)", ctx do
    #   ctx.playlist
    #   |> Playlist.active()
    #   |> Should.Be.equal(:none)
    # end
  end

  describe "Carol.Playlist.active_id/1" do
    @tag program_add: :live_programs, playlist_add: []
    # @tag dump: [:programs, :playlist]
    test "returns active id when there's a live program and next ms > 1000", ctx do
      ctx.playlist
      |> Playlist.active_id()
      |> Should.Be.equal("Live")
    end

    @tag program_add: :live_quick_programs, playlist_add: []
    test "returns :keep when there's a live program and next ms < 1000", ctx do
      ctx.playlist
      |> Playlist.active_id()
      |> Should.Be.equal(:keep)
    end

    @tag program_add: :future_programs, playlist_add: []
    test "returns :none when all programs are in the future", ctx do
      ctx.playlist
      |> Playlist.active_id()
      |> Should.Be.equal(:none)
    end
  end

  def dump(%{dump: keys} = ctx) when is_list(keys) do
    ["\n", Atom.to_string(ctx.test), "\n"] |> IO.puts()

    for key <- keys do
      to_dump = ctx[key] || []
      dump_specific(to_dump)
    end

    :ok
  end

  def dump(_), do: :ok

  def dump_specific([%Carol.Program{} | _] = programs) do
    for p <- programs do
      [p.id, "\n  ", inspect(p.start.at), "\n  ", inspect(p.finish.at), "\n"] |> IO.puts()
    end
  end

  def dump_specific(playlist) when is_map(playlist) do
    for {_id, e} <- playlist do
      [e.id, " ", inspect(e.type), " ", inspect(e.ms)] |> IO.puts()
    end
  end

  # defp freshen_playlist(%{program_add: _} = ctx) do
  #   Process.sleep(10)
  #
  #   ctx
  #   |> Map.take([:program_add, :playlist_add])
  #   |> then(fn ctx -> Map.merge(ctx, opts_add(ctx)) end)
  #   |> then(fn ctx -> Map.merge(ctx, program_add(ctx)) end)
  #   |> then(fn ctx -> Map.merge(ctx, playlist_add(ctx)) end)
  #   |> Map.get(:playlist)
  # end

  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)

  defp playlist_add(ctx) do
    case ctx do
      %{playlist_add: [], programs: programs, opts: opts} ->
        programs
        |> Carol.Program.flatten(opts)
        |> then(fn list -> %{playlist: Playlist.new(list)} end)

      _ ->
        :ok
    end
  end

  defp program_add(ctx) do
    case Carol.ProgramAid.add(ctx) do
      %{programs: programs} ->
        programs
        |> Carol.Program.analyze_all(ctx.opts)
        |> then(fn programs -> %{programs: programs} end)

      :ok ->
        :ok
    end
  end
end
