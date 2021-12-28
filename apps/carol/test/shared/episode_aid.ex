defmodule Carol.EpisodeAid do
  @moduledoc """
  Create one or more `Episode`s to merge into the test context
  """

  alias Carol.Episode

  @shift_opts [:days, :hours, :minutes, :seconds, :milliseconds, :microseconds]
  @tz "America/New_York"

  @many [:future, :mixed, :past, :short]
  @single [:single_future, :single_now, :single_past]
  @sim [:porch, :greenhouse]
  def add(%{episodes_add: {what, epi_opts}, opts: opts})
      when is_list(epi_opts)
      when is_list(opts) do
    opts_all = if(is_list(epi_opts), do: epi_opts ++ opts, else: opts)
    {analyze?, opts_all} = Keyword.pop(opts_all, :analyze, true)

    case {what, epi_opts} do
      {x, _} when x in @many -> make_many(what, opts_all)
      {x, _} when x in @single -> make_single(what, opts_all)
      {:sim, opt} when opt in @sim -> make_sim(opt)
      {:events, opts} -> make_events(opts)
    end
    |> wrap_episodes(analyze?, opts)
  end

  def add(_), do: :ok

  @make_events Solar.event_opts(:binaries)
  def make_events(events) do
    for tuple when elem(tuple, 1) in @make_events <- events do
      case tuple do
        {id, event} -> [id: id, event: event]
        {id, event, shift} -> [id: id, event: event, shift: shift]
      end
      |> then(fn args -> args ++ [execute: :on] end)
      |> Episode.new()
    end
  end

  @make_many_type [:future, :now, :past, :yesterday]
  def make_many(type, opts) when type in @make_many_type do
    {want_count, rest} = Keyword.pop(opts, :count, 1)
    {sched_opts, rest} = Keyword.split(rest, [:ref_dt, :timezone])
    {shift_opts, rest} = Keyword.split(rest, @shift_opts)

    shift_opts = make_many_shift_opts(type, shift_opts)

    for x <- 1..want_count do
      shift_opts = shift_multiply(shift_opts, x)

      id = id_from_counter(type, x)
      event = fixed(type, sched_opts ++ shift_opts)
      execute = [cmd: :on]

      Keyword.merge(rest, id: id, event: event, execute: execute)
      |> Episode.new()
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

  @shift_short [milliseconds: 130]
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

  def make_single(what, opts) do
    # single requested, ensure count == 1
    opts = Keyword.put(opts, :count, 1)

    case what do
      :single_future -> make_many(:future, opts)
      :single_now -> make_many(:now, opts)
      :single_past -> make_many(:past, opts)
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp adjust_future_when_have_now(episodes) do
    have_now? = Enum.any?(episodes, fn %{id: id} -> id =~ ~r/Now/ end) && :have_now

    for %{id: id, shift: shift} = episode <- episodes, reduce: {have_now?, []} do
      {:have_now, acc} ->
        if id =~ ~r/Future/ do
          seconds = Keyword.get(shift, :seconds, 0)

          struct(episode, shift: Keyword.put(shift, :seconds, seconds + 3))
        else
          episode
        end
        |> then(fn episode -> {:have_now, [episode | acc]} end)

      {x, acc} ->
        {x, [episode | acc]}
    end
    |> then(fn {_, episodes} -> episodes end)
  end

  @fixed_types [:future, :now, :past, :yesterday]
  defp fixed(what, opts) when what in @fixed_types do
    {dt, rest} = Keyword.pop(opts, :ref_dt, Timex.now(@tz))
    {shift_opts, _} = Keyword.split(rest, @shift_opts)

    case what do
      x when x in [:future, :past] -> shift_adjust(shift_opts, what)
      :now -> []
      :yesterday -> [days: -1]
    end
    |> then(fn shift_opts -> Timex.shift(dt, shift_opts) end)
    |> to_asn1()
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

  defp shift_adjust(opts, :future), do: opts

  defp shift_adjust(opts, :past) do
    Enum.map(opts, fn {unit, val} -> {unit, val * -1} end)
  end

  defp shift_multiply(opts, counter) do
    for {k, v} <- opts do
      case {k, v} do
        {k, v} when k in @shift_opts -> {k, v * counter}
        kv -> kv
      end
    end
  end

  defp to_asn1(%DateTime{} = dt), do: Timex.format!(dt, "{ASN1:GeneralizedTime:Z}")

  defp wrap_episodes(episodes, true = _analyze?, opts) do
    Carol.Episode.analyze_episodes(episodes, opts) |> wrap_episodes()
  end

  # when analyze is false just calc_at
  defp wrap_episodes(episodes, false = _analyze?, opts) do
    for episode <- episodes do
      Carol.Episode.calc_at(episode, opts)
    end
    |> wrap_episodes()
  end

  defp wrap_episodes(episodes) do
    %{episodes: adjust_future_when_have_now(episodes) |> Carol.Episode.sort(:ascending)}
  end
end
