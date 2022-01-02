defmodule Carol.Episode do
  alias __MODULE__

  defstruct id: "", execute: [], event: "", at: :none, shift: [], valid: :unchecked, defaults: []

  @type t :: %__MODULE__{
          id: String.t(),
          execute: :on | :off | list(),
          event: String.t(),
          shift: Timex.shift_options(),
          valid: :unchecked | :yes | {:no, String.t()},
          defaults: [] | keyword()
        }

  defmacrop ref_dt do
    quote do
      Keyword.get(var!(opts), :ref_dt)
    end
  end

  @doc since: "0.3.0"
  def active_id([%Episode{id: id} | _]), do: id
  def active_id(_), do: :none

  @doc since: "0.3.0"
  # (1 of 3) episodes require first calc_at
  def analyze_episodes([%Episode{at: :none} | _] = episodes, sched_opts) do
    for %Episode{} = episode <- episodes do
      calc_at(episode, sched_opts)
    end
    |> sort(:ascending)
    |> analyze_episodes(sched_opts)
  end

  # (2 of 3) nominal operation, one or more episodes
  def analyze_episodes([%Episode{} | _] = episodes, opts) do
    # NOTE: reverse the list since we are searching for the first episode before ref_dt.  if we
    # searched the list forward we'd have to look ahead in the list resulting in a complex reduction.
    episodes = Enum.reverse(episodes)

    for episode <- episodes, reduce: %{active: [], rest: []} do
      # the first episode found that starts before the ref_dt is considered active
      %{active: []} = acc -> accumulate_active(episode, acc, opts)
      # once an active episode is located the remaining episodes are simply accumulated
      %{active: %Episode{}} = acc -> accumulate_rest(episode, acc)
    end
    |> check_analysis(opts)
    |> sort(:ascending)
  end

  # (3 of 3) no episodes or bad config
  def analyze_episodes(_, _opts), do: []

  defp accumulate_active(episode, acc, opts) do
    # the first episode found before the ref_dt is active
    if Timex.compare(episode.at, ref_dt()) <= 0 do
      %{acc | active: episode}
    else
      accumulate_rest(episode, acc)
    end
  end

  defp accumulate_rest(episode, acc), do: %{acc | rest: [episode | acc.rest]}

  # good, we have an active episode. not much to do here except futurize past episodes
  defp check_analysis(%{active: %Episode{} = active, rest: rest}, opts) do
    futurize(active, rest, opts)
  end

  # drat, we didn't find an active episode. this occurs at startup before we've
  # stablized the episode list (e.g. keeping active always at the head)
  defp check_analysis(%{active: [], rest: episodes}, opts) do
    # since we didn't find an active episode we know all episodes are in the
    # future relative to ref_dt and the list is not yet stable.

    # since Carol operates on a 24h clock one of the future episodes is the
    # active episode when they are moved to the past.  in other words, in a
    # stable list the passage of time activates each episode and moves the
    # previously active episode to the future.

    # sort the list of future episodes descending so the last episode of the 24 hour
    # clock is at the head.
    [future_active | future_rest] = sort(episodes, :descending)

    # move the future active to the previous day using calc_at/3
    # NOTE: always use calc_at to ensure accurate at calculation based on the event
    active = calc_at(future_active, {:days, -1}, opts)

    # NOTE: analyze_episodes/2 will create sort episodes to create stable list
    [active | future_rest]
  end

  @doc since: "0.3.0"
  # (1 of 3) calculate episode using ref_dt in opts
  def calc_at(%Episode{} = ep, opts) when is_list(opts) do
    [event: ep.event, shift_opts: ep.shift]
    |> Keyword.merge(opts)
    |> Carol.Episode.Event.parse()
    |> then(fn at -> struct(ep, at: at) end)
  end

  def calc_at(%Episode{} = episode, {:days, days}, opts) when is_integer(days) and is_list(opts) do
    # days is > 0 ; shift ref_dt forward by days then calc_at
    next_ref_dt = ref_dt() |> Timex.shift(days: days)
    next_opts = Keyword.put(opts, :ref_dt, next_ref_dt)

    calc_at(episode, next_opts)
  end

  @doc since: "0.3.0"
  def execute_args(extra_opts, :active, episodes)
      when is_list(extra_opts)
      when is_list(episodes) do
    List.first(episodes) |> execute_args(extra_opts)
  end

  def execute_args(extra_opts, want_id, episodes)
      when is_list(extra_opts)
      when is_binary(want_id)
      when is_list(episodes) do
    Enum.find(episodes, [], fn %{id: id} -> id == want_id end)
    |> execute_args(extra_opts)
  end

  def execute_args(%Episode{execute: args, defaults: defaults}, extra_opts) do
    execute_defaults = Keyword.get(defaults, :execute, [])
    {args ++ extra_opts, execute_defaults}
  end

  def execute_args([], _), do: {[], []}

  @doc since: "0.3.0"
  def ms_until_next_episode([%Episode{} = episode | rest], opts) do
    # next_ms = Timex.diff(ref_dt(), episode.at, :milliseconds)
    next_ms = Timex.diff(episode.at, ref_dt(), :milliseconds)

    # NOTE: this will recurse 99% of the time because the first element is the active episode
    # and therefore a negative number.  there could be, however, situations that are not obvious
    # where the first element returns a positive number. that said, we always check the first element.

    case next_ms do
      x when x <= 0 -> ms_until_next_episode(rest, opts)
      x -> x
    end
  end

  def ms_until_next_episode(_, _opts), do: 1000

  @doc since: "0.3.0"
  def new_from_episode_list([_ | _rest] = episodes, defaults) do
    Enum.map(episodes, fn episode_args -> new(episode_args, defaults) end)
  end

  def new_from_episode_list(_, _defaults), do: []

  @doc since: "0.3.0"
  @new_fields [:id, :execute, :shift, :event, :defaults]
  def new(args, defaults \\ [])

  def new(args, defaults) when is_list(args) and is_list(defaults) do
    args
    |> Keyword.put_new(:defaults, defaults)
    |> List.flatten()
    |> Keyword.take(@new_fields)
    |> then(fn fields -> struct(Episode, fields) end)
  end

  def new(%Episode{} = episode, []), do: episode

  def put_execute({want_id, execute}, episodes) do
    # reverse the list so the result is in the same order (instead of sorting)
    episodes = Enum.reverse(episodes)

    for %{id: id} = episode <- episodes, reduce: [] do
      acc when id == want_id -> [struct(episode, execute: execute) | acc]
      acc -> [episode | acc]
    end
  end

  @doc """
  Sort `Episode` list in ascending order by calculated `DateTime`

  Only lists with two or more elements are sorted.  Lists less than two elements are
  passed through unchanged.

  """
  @doc since: "0.3.0"
  @spec sort([Episode.t(), ...], order :: :ascending | :descending) :: [Episode.t(), ...]
  @sort_order [:ascending, :descending]
  def sort([_e0, _e1 | _rest] = episodes, order) when order in @sort_order do
    # flatten the list to remove any empty lists added during check_analysis/2
    episodes = List.flatten(episodes)

    case order do
      :ascending -> Enum.sort(episodes, &ascending/2)
      :descending -> Enum.sort(episodes, &descending/2)
    end
  end

  def sort(episodes, _order), do: episodes

  @doc since: "0.3.0"
  def status_map(%Episode{at: at, id: id}, opts) do
    diff_ms = Timex.diff(at, ref_dt(), :milliseconds)

    case diff_ms do
      x when x <= 0 -> {:elapsed_ms, abs(diff_ms)}
      x when x > 0 -> {:till_ms, diff_ms}
    end
    |> then(fn {key, ms} -> %{key => ms, id: id} end)
  end

  @doc since: "0.3.0"
  def status_from_list(episodes, opts) when is_list(episodes) do
    {status_opts, opts_rest} = Keyword.split(opts, [:format])

    status_opts_map = Enum.into(status_opts, %{})

    for %Episode{} = episode <- episodes do
      status_map = status_map(episode, opts_rest)

      case status_opts_map do
        %{format: :humanized} -> format_status_map(status_map, :humanized)
        _ -> status_map
      end
    end
  end

  @doc false
  def ascending(%Episode{at: lhs}, %Episode{at: rhs}), do: Timex.compare(lhs, rhs) <= 0

  @doc false
  def descending(%Episode{at: lhs}, %Episode{at: rhs}), do: Timex.compare(lhs, rhs) >= 0

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp format_status_map(%{id: id, till_ms: ms}, :humanized) do
    base = ["'#{id}' will start"]

    case ms do
      x when x < 1000 -> ["in less than a second"]
      _ -> ["in", humanize_ms(ms)]
    end
    |> then(fn details -> base ++ details end)
    |> Enum.join(" ")
  end

  defp format_status_map(%{id: id, elapsed_ms: ms}, :humanized) do
    base = ["'#{id}'"]

    case ms do
      x when x == 0 -> ["just started"]
      x when x < 1000 -> ["started less than a second ago"]
      _ -> ["started", humanize_ms(ms), "ago"]
    end
    |> then(fn details -> base ++ details end)
    |> Enum.join(" ")
  end

  # (1 of 4) ensure a single episode is moved to the future by performing
  # calc_at until the episode at is greater than or equal to ref_dt
  # defp futurize(%Episode{} = episode, opts) do
  #   # a calc_at with current ref_dt might bring the episode into the future
  #   new_episode = calc_at(episode, {:days, 0}, opts)
  #   compare_tuple = futurize_compare_tuple(new_episode, opts)
  #
  #   # check if episode moved to the future
  #   futurize(episode, compare_tuple, opts)
  # end

  # (1 of 3) ensure a list of episodes are moved to the future using futurize/2
  # then return the stable episode list (active at head)
  # NOTE: does not change the active episode
  defp futurize(%Episode{} = active, episodes, opts) when is_list(episodes) do
    for %Episode{} = episode <- episodes, reduce: [active] do
      acc ->
        compare = futurize_compare(episode, opts)

        [futurize(episode, compare, opts) | acc]
    end
  end

  # (2 of 3) futurizing complete; the episode is in the future (or now)
  defp futurize(%Episode{} = episode, compare, _opts) when compare in [:lt, :eq] do
    episode
  end

  # (3 of 3) the episode is in the past; execute calc_at with an accumulator of
  # the count of days into the future.
  defp futurize(%Episode{} = episode, :gt, opts) do
    days = Keyword.get(opts, :futurize_days, 0)

    new_episode = calc_at(episode, {:days, days}, opts)

    # create compare tuple, store futurize_days and recurse
    compare = futurize_compare(new_episode, opts)
    next_futurize_opts = Keyword.put(opts, :futurize_days, days + 1)
    futurize(new_episode, compare, next_futurize_opts)
  end

  defp futurize_compare(%{at: at}, opts), do: DateTime.compare(ref_dt(), at)

  defp humanize_ms(ms) do
    Timex.Duration.from_milliseconds(ms)
    |> Timex.Duration.to_seconds()
    |> trunc()
    |> Timex.Duration.from_seconds()
    |> Timex.format_duration(:humanized)
  end
end
