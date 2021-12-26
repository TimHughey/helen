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
  defp check_analysis(%{active: [], rest: episodes}, _opts) do
    # since we didn't find an active episode we know all episodes are in the
    # future relative to ref_dt and the list is not yet stable.

    # since Carol operates on a 24h clock one of the future episodes is the
    # active episode when they are moved to the past.  in other words, in a
    # stable list the passage of time activates each episode and moves the
    # previously active episode to the future.

    # move all episodes to the past and sort descending to reveal the
    # episode in the most recent past (at the head of the list).  we take active
    # out of the list then send the tail through futurize to create a stable list
    episodes = sort(episodes, :descending)
    active = hd(episodes) |> shift_past()

    [active | tl(episodes)]
    |> sort(:ascending)
  end

  @doc since: "0.3.0"
  def calc_at(%Episode{} = ep, opts \\ []) when is_list(opts) do
    [event: ep.event, shift_opts: ep.shift]
    |> Keyword.merge(opts)
    |> Carol.Episode.Event.parse()
    |> then(fn at -> struct(ep, at: at) end)
  end

  @doc since: "0.3.0"
  def execute_args(want_id, episodes) when is_list(episodes) do
    case want_id do
      :active -> List.first(episodes)
      x when is_binary(x) -> Enum.find(episodes, fn %{id: id} -> id == want_id end)
    end
    |> finalize_execute_args()
  end

  defp finalize_execute_args(%Episode{id: id, execute: execute, defaults: defaults}) do
    execute = Keyword.put_new(execute, :cmd, id)
    defaults = defaults[:execute] || []

    if(defaults != [], do: [defaults: defaults], else: [])
    |> Keyword.merge(execute)
  end

  defp finalize_execute_args(_), do: []

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

  # move any episode in the past to the future but don't touch active
  defp futurize(%Episode{id: active_id} = active, [%Episode{} | _] = episodes, opts) do
    # NOTE: the episode list passed in may include the active episode
    # so we must exclude it from being futurized.
    for %Episode{id: id} = episode when id != active_id <- episodes do
      futurize(episode, opts)
    end
    # add the active episode to the final list
    |> then(fn episodes -> [active | episodes] end)
    |> sort(:ascending)
  end

  # handle single episode lists
  defp futurize(%Episode{at: at} = episode, [], opts) do
    # NOTE: when the active episode is one or more days in the past when
    # bring it current
    days_diff = Timex.diff(ref_dt(), at, :days)

    case days_diff do
      x when x < 0 -> shift(episode, days: abs(days_diff))
      _ -> episode
    end
    |> List.wrap()
  end

  # futurize an episode
  defp futurize(%{at: at} = episode, opts) do
    (Timex.before?(at, ref_dt()) && calc_at(episode, tomorrow_opts(opts))) || episode
  end

  defp humanize_ms(ms) do
    Timex.Duration.from_milliseconds(ms)
    |> Timex.Duration.to_seconds()
    |> trunc()
    |> Timex.Duration.from_seconds()
    |> Timex.format_duration(:humanized)
  end

  defp shift(%Episode{at: at} = episode, shift_opts) do
    struct(episode, at: Timex.shift(at, shift_opts))
  end

  defp shift_past(%Episode{} = episode), do: shift(episode, days: -1)

  defp tomorrow_opts(opts) do
    ref_dt()
    |> Timex.shift(days: 1)
    |> then(fn tomorrow -> Keyword.put(opts, :ref_dt, tomorrow) end)
  end
end
