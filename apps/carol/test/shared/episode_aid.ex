defmodule Carol.EpisodeAid do
  @moduledoc false

  alias Carol.Episode

  @shift_opts [:days, :hours, :minutes, :seconds, :milliseconds, :microseconds]
  @tz "America/New_York"

  def add(%{episodes_add: {what, epi_opts}} = ctx) do
    ref_dt = Timex.now(@tz)

    opts = ctx[:opts] || [alfred: AlfredSim, timezone: @tz, ref_dt: ref_dt]

    %{episodes: add(what, epi_opts, opts), opts: opts, ref_dt: ref_dt}
  end

  def add(_), do: :ok

  @many [:future, :mixed, :past, :short]
  @single [:single_future, :single_now, :single_past, :whole_day]
  @sim [:porch, :greenhouse]
  def add(what, epi_opts, opts) do
    opts_all = if(is_list(epi_opts), do: epi_opts ++ opts, else: opts)
    {analyze?, opts_all} = Keyword.pop(opts_all, :analyze, true)

    case {what, epi_opts} do
      {x, _} when x in @many -> make_many(what, opts_all)
      {x, _} when x in @single -> make_single(what, opts_all)
      {:sim, opt} when opt in @sim -> make_sim(opt)
      {:events, opts} -> make_events(opts)
    end
    # NOTE: list order critical.  must adjust future before analyze or calc_at!
    |> preprocess([adjust_future: what != :short, analyze: analyze?], opts)
  end

  @solar_events Solar.event_opts(:binaries)
  def make_events(events) do
    Enum.map(events, fn
      {id, event} when event in @solar_events -> [id: id, event: event]
      {id, event, shift} -> [id: id, event: event, shift: shift]
    end)
    |> Carol.Episode.new_from_list(execute: [cmd: :on])
  end

  @make_many_type [:future, :now, :past, :yesterday]
  def make_many(type, opts) when type in @make_many_type do
    {want_count, rest} = Keyword.pop(opts, :count, 1)
    {sched_opts, rest} = Keyword.split(rest, [:ref_dt, :timezone])
    {shift_opts, rest} = Keyword.split(rest, @shift_opts)

    all_opts = make_many_shift_opts(type, shift_opts) ++ sched_opts

    for count <- 1..want_count do
      # apply count multiplier to all shift opts to move the event forward or backward in time
      fixed_opts = Enum.map(all_opts, fn {k, v} -> (k in @shift_opts && {k, v * count}) || {k, v} end)

      rest
      |> Keyword.merge(
        id: id_from_counter(type, count),
        event: fixed(type, fixed_opts),
        execute: [opts: [ack: :host]]
      )
      |> Episode.new(execute: [cmd: :on])
    end
  end

  def make_many(:mixed, opts) do
    {mix_opts, opts_rest} = Keyword.split(opts, [:future, :now, :past, :yesterday])

    for {what, count} <- mix_opts do
      many_opts = [count: count] ++ opts_rest

      case what do
        x when x in [:future, :past, :yesterday] -> make_many(what, many_opts)
        :now -> make_many(:now, opts_rest)
      end
    end
    |> List.flatten()
  end

  # NOTE: include seconds: 0 so make_many_shift_opts/2 doesn't add seconds to
  # shift opts prior to calling fixed/2
  @shift_short [milliseconds: 250, seconds: 0]
  def make_many(:short, opts) do
    {mix_opts, opts_rest} = Keyword.split(opts, [:future, :now, :past])

    for {what, count} <- mix_opts do
      many_opts = [count: count] ++ opts_rest

      case what do
        :future -> make_many(:future, many_opts ++ @shift_short)
        :now -> make_many(:now, opts_rest)
        :past -> make_many(:past, many_opts ++ @shift_short)
      end
    end
    |> List.flatten()
  end

  def make_sim(what) do
    cond do
      what == :porch ->
        [{"Day", "astro rise"}, {"Evening", "sunset"}, {"Overnight", "astro set"}]
        |> make_events()

      what == :greenhouse ->
        [{"Day", "astro rise"}, {"Night", "astro rise", [hours: 13]}]
        |> make_events()

      true ->
        []
    end
  end

  @begin_day "beginning of day"
  @whole_day [id: "All Day", event: @begin_day, execute: [cmd: :on]]
  def make_single(what, opts) do
    # single requested, ensure count == 1
    opts = Keyword.put(opts, :count, 1)

    case what do
      :single_future -> make_many(:future, opts)
      :single_now -> make_many(:now, opts)
      :single_past -> make_many(:past, opts)
      :whole_day -> [Episode.new(@whole_day, [])]
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp adjust_future_when_have_now(episodes) do
    if Enum.any?(episodes, &match?(%{id: <<"Now"::binary, _::binary>>}, &1)) do
      Enum.map(episodes, fn
        %{id: <<"Future"::binary, _rest::binary>>, shift: shift_opts} = episode ->
          {_, opts} = Keyword.get_and_update(shift_opts, :seconds, fn x -> {x, (x || 0) + 3} end)

          struct(episode, shift: opts)

        episode ->
          episode
      end)
    else
      episodes
    end
  end

  @fixed_types [:future, :now, :past, :yesterday]
  defp fixed(what, opts) when what in @fixed_types do
    {ref_dt, rest} = Keyword.pop(opts, :ref_dt, Timex.now(@tz))
    {shift_opts, _} = Keyword.split(rest, @shift_opts)

    case what do
      x when x in [:future, :past] -> shift_adjust(shift_opts, what)
      :now -> []
      :yesterday -> [days: -1]
    end
    |> to_asn1(ref_dt)
  end

  defp id_from_counter(what, counter) do
    what = Atom.to_string(what) |> String.capitalize()

    case what do
      x when x in ["Future", "Now", "Yesterday"] -> counter
      "Past" -> counter * -1
    end
    |> then(fn counter -> [what, to_string(counter)] end)
    |> Enum.join(" ")
  end

  defp make_many_shift_opts(type, opts) do
    case {type, opts} do
      {:now, _} -> []
      {:past, opts} -> Keyword.put_new(opts, :seconds, 2)
      {:future, opts} -> Keyword.put_new(opts, :seconds, 3)
      {:yesterday, _} -> []
    end
  end

  defp shift_adjust(opts, what) do
    case what do
      :past -> Enum.map(opts, fn {unit, val} -> {unit, val * -1} end)
      _ -> opts
    end
  end

  defp to_asn1(shift_opts, %DateTime{} = dt) do
    Timex.shift(dt, shift_opts)
    |> Timex.format!("{ASN1:GeneralizedTime:Z}")
  end

  def preprocess(episodes, wrap_opts, opts) do
    Enum.reduce(wrap_opts, episodes, fn
      {:adjust_future, true}, acc -> adjust_future_when_have_now(acc)
      {:analyze, true}, acc -> Carol.Episode.analyze_episodes(acc, opts)
      {:analyze, false}, acc -> Enum.map(acc, &Carol.Episode.calc_at(&1, opts))
      {:adjust_future, false}, acc -> acc
      _, acc -> acc
    end)
  end
end
