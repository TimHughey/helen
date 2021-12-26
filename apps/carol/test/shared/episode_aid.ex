defmodule Carol.EpisodeAid do
  @moduledoc """
  Create one or more `Episode`s to merge into the test context
  """

  alias Carol.Episode

  @shift_opts [:days, :hours, :minutes, :seconds, :milliseconds, :microseconds]
  @tz "America/New_York"

  @many [:future, :mixed, :past, :short]
  @single [:single_future, :single_now, :single_past]
  def add(%{episodes_add: {what, epi_opts}, opts: opts})
      when is_list(epi_opts)
      when is_list(opts) do
    opts_all = epi_opts ++ opts

    case what do
      x when x in @many -> make_many(what, opts_all)
      x when x in @single -> make_single(what, opts_all)
    end
    |> wrap_return(opts)
  end

  def add(_), do: :ok

  @make_many_type [:future, :now, :past]
  def make_many(type, opts) when type in @make_many_type do
    {want_count, rest} = Keyword.pop(opts, :count, 1)
    {sched_opts, rest} = Keyword.split(rest, [:ref_dt, :timezone])
    {shift_opts, rest} = Keyword.split(rest, @shift_opts)
    #  {shift_opts,opts_rest} = Keyword.split(opts_rest, @shift_opts)

    shift_opts = (shift_opts == [] && [seconds: 1]) || shift_opts

    for x <- 1..want_count do
      shift_opts = shift_multiply(shift_opts, x)

      id = id_from_counter(type, x)
      event = fixed(type, sched_opts ++ shift_opts)
      execute = [cmd: :on]

      Keyword.merge(rest, id: id, event: event, execute: execute)
      |> Episode.new()
    end
  end

  @shift_mixed [seconds: 2]
  def make_many(:mixed, opts) do
    {mix_opts, opts_rest} = Keyword.split(opts, [:future, :now, :past])

    for {what, count} <- mix_opts do
      many_opts = [count: count] ++ opts_rest

      case what do
        :future -> make_many(:future, many_opts ++ @shift_mixed)
        :now -> make_many(:now, opts_rest)
        :past -> make_many(:past, many_opts ++ @shift_mixed)
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

  defp fixed(what, opts) when what in [:future, :now, :past] do
    {dt, rest} = Keyword.pop(opts, :ref_dt, Timex.now(@tz))
    {shift_opts, _} = Keyword.split(rest, @shift_opts)

    case what do
      x when x in [:future, :past] -> shift_adjust(shift_opts, what)
      :now -> []
    end
    |> then(fn shift_opts -> Timex.shift(dt, shift_opts) end)
    |> to_asn1()
  end

  defp id_from_counter(what, counter) do
    [Atom.to_string(what) |> String.capitalize(), to_string(counter)]
    |> Enum.join(" ")
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

  defp wrap_return([%Episode{} | _] = episodes, opts) do
    episodes
    |> Enum.map(fn episode -> Carol.Episode.calc_at(episode, opts) end)
    |> Carol.Episode.sort(:ascending)
    |> then(fn episodes -> %{episodes: episodes} end)
  end
end
