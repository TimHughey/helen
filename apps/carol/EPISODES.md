# Episode List (aka Episodes)

The `Episode` list depicts a series of actions that occur at specific points on a 24 hour clock. The
episode list is "played" in sequential order at a precise time of day.

The concept of "playing" episodes is the core of how `Carol` determines the active episode.

An episode is active when:

- The active criteria of `ref_dt >= episode time` is met.
- Until another episode meets the active criteria.

Simple.

But, as we all know, time never stands still. Eventually another episode will meet the active criteria and becomes active.

The previously active episode becomes inactive and is in the past with no opportunity to ever meet the active criteria. To solve that problem the episode is `futurized` and returned to the episode list to be "played" again in the future.

The passage of time clicks this process forward creating a never ending sequence of episodes with:

- One episode always active
- Some number of episodes to play in the future.

This never ending sequence of episodes is called the `stable list`.

> `Carol.Episode.analyze_episodes/2` maintains the stable list where
> `hd/1` is the active episode and `tl/1` are future episodes.

## Maintaining the episode list

Maintaining a stable `Episode` list is trivial due to the passage of time and because the episode list
is constrained to a 24 hour clock. In other words, as time passes there is **always** an active episode.
This is true even when the episode list is a single element.

The complexity of **creating** a stable `Episode` list is directly related on the time of day the server is started.
