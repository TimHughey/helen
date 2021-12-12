defmodule Carol.Playlist.Entry do
  alias __MODULE__

  @moduledoc """
  Playlist Entry
  """

  defstruct id: :none, type: :none, ms: :none, timer: :none, timer_ms: :none

  @type t :: %__MODULE__{
          id: String.t(),
          type: :none | :active | :next,
          ms: :none | pos_integer(),
          timer: :none | reference(),
          timer_ms: :none | pos_integer()
        }

  @doc since: "0.2.1"
  def add_timer_ms(%Entry{timer: t} = entry, true) when is_reference(t) do
    struct(entry, timer_ms: Process.read_timer(entry.timer))
  end

  def add_timer_ms(entry, _), do: entry

  def cancel_timer(%Entry{timer: t} = entry) when is_reference(t) do
    timer_ms = Process.cancel_timer(t)

    struct(entry, timer: :none, timer_ms: timer_ms)
  end

  def cancel_timer(entry), do: entry

  @new_fields [:id, :type, :ms]
  def new(fields_list) when is_list(fields_list) do
    {fields, _extra} = Keyword.split(fields_list, @new_fields)

    struct(%Entry{}, fields)
  end
end

defmodule Carol.Playlist do
  @moduledoc """
  Process a playlist map
  """

  alias Carol.Playlist.Entry

  @doc since: "0.2.1"
  @active_opts [timer_ms: true]
  def active(playlist, opts \\ @active_opts) when is_map(playlist) when is_list(opts) do
    {timer_ms?, _opts_rest} = Keyword.pop(opts, :timer_ms, true)

    for {_id, %Entry{type: :active} = entry} <- playlist do
      Entry.add_timer_ms(entry, timer_ms?)
    end
    |> List.first(:none)
  end

  @doc """
  Return the active `id` from a playlist

  ## Example
  ```
  # using the provided playlist determine the active id
  Playlist.active_id(playlist)
  #=> :keep, :none or the active id

  ```
  """
  @doc since: "0.2.1"
  def active_id(playlist) when is_map(playlist) do
    case %{active: active(playlist), next: next_first(playlist)} do
      %{active: :none, next: %{timer_ms: x}} when x < 1000 -> :keep
      %{active: %{id: id}} -> id
      _ -> :none
    end

    # cond do
    #   # nothing active and pending msg, programs should flow seamlessly
    #   now.active == :none and is_struct(prev.next) and prev.next.timer_ms < 1000 -> :keep
    #   # there's an active program, return it's id
    #   is_struct(now.active) -> now.active.id
    #   # nothing active or other special condition
    #   true -> :none
    # end
    # |> then(fn id -> {id, play_new} end)
  end

  @doc since: "0.2.1"
  def new(entries) when is_list(entries) do
    for fields when is_list(fields) <- entries, into: %{} do
      {fields[:id], Entry.new(fields)}
    end
    |> ensure_timers()
  end

  @doc since: "0.2.1"
  @next_opts [timer_ms: true]
  def next_first(playlist, opts \\ @next_opts) when is_map(playlist) when is_list(opts) do
    {timer_ms?, _opts_rest} = Keyword.pop(opts, :timer_ms, true)

    next_sorted(playlist)
    |> List.first(:none)
    |> Entry.add_timer_ms(timer_ms?)
  end

  @doc since: "0.2.1"
  def refresh(now_entries, prev_pl) do
    # prevent spurious timers from earlier playlists
    clear(prev_pl)

    now_entries |> new()
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp clear(playlist) when is_map(playlist) do
    for {key, entry} <- playlist, into: %{} do
      {key, Entry.cancel_timer(entry)}
    end
  end

  defp clear(passthrough), do: passthrough

  defp ensure_timers(playlist) do
    for {key, entry} <- playlist, into: %{} do
      {key, start_one_timer(entry)}
    end
  end

  defp next_sorted(playlist) do
    for({_key, %Entry{type: :next} = entry} <- playlist, do: entry)
    |> Enum.sort(fn e1, e2 -> e1.ms <= e2.ms end)
  end

  defp start_one_timer(entry) do
    send_after = fn msg, ms -> Process.send_after(self(), msg, ms) end

    case Entry.cancel_timer(entry) do
      %{type: :active} -> :finish_id
      %{type: :next} -> :start_id
    end
    |> then(fn msg_atom -> send_after.({msg_atom, entry.id}, entry.ms) end)
    |> then(fn ref -> struct(entry, timer: ref) end)
  end
end
