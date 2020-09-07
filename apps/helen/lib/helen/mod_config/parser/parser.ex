defmodule Helen.Config.Parser do
  @moduledoc """
  Parses configuration text files
  """

  require Logger

  alias Helen.Config.Parser

  import Helen.Time.Helper, only: [to_duration: 1]
  import Parser.Regex, only: [regex: 1]

  def parse(raw) when is_binary(raw) do
    raw
    |> list_of_lines()
    |> parse_lines()
  end

  defp list_of_lines(raw) do
    for line <- String.split(raw, "\n") do
      # two_spaces = "  "
      #
      # String.replace(line, "\t", two_spaces)
      line
    end
  end

  defp parse_lines(lines) do
    metric_map = %{count: 0, lines: []}

    for line <- lines,
        reduce: %{
          config: %{},
          parser: %{
            line_num: 0,
            line: "",
            blanks: metric_map,
            empties: metric_map,
            comments: metric_map,
            unmatched: metric_map,
            match: %{},
            syntax: :ok,
            errors: [],
            context: :top_level,
            modes: nil
          }
        } do
      # found a syntax / parse error so skip this line
      %{parser: %{syntax: :error}} = opts ->
        opts

      # syntax is :ok thus far, parse the line
      %{parser: %{syntax: :ok}} = opts ->
        # store the line and line number we're parsing then parse
        # the actual line
        opts
        |> put_in([:parser, :line], line)
        |> update_in([:parser, :line_num], fn x -> x + 1 end)
        |> match_line()
        |> normalize_captures()
        |> parse_line()
    end
    |> validate_syntax()
    |> log_errors()
  end

  def syntax_ok?(%{parser: %{syntax: :ok}}), do: true
  def syntax_ok?(_state), do: false

  def match_line(%{parser: %{context: context, line: line}} = opts) do
    opts |> put_in([:parser, :match], run_regex(context, line))
  end

  @doc false
  # determine what regex to match based on the current context
  def regex_list(context) do
    case context do
      :top_level ->
        regex([:top_level, :end_of_list])

      x when x in [:base, :workers, :cmd_definitions, :modes, :steps] ->
        regex([:top_level, context, :end_of_list])

      :actions ->
        # must include steps matches to detect when a new step is defined
        regex([:top_level, context, :steps, :modes, :end_of_list])

      _x ->
        regex([:top_level, :end_of_list])
    end
  end

  def run_regex(context, line) do
    for %{context: _, stmt: _, norm: _, re: re} = regex_def <-
          regex_list(context),
        reduce: %{} do
      # we've had a match and have captures, quickly spool through the
      # remainder of the list and don't run the remaining regex
      %{captures: captures} = acc when is_map(captures) ->
        acc

      acc ->
        case Regex.named_captures(re, line, capture: :all_but_first) do
          raw when is_map(raw) ->
            # stuff the captures with their map keys atomized into the
            # regex definition that just matched
            put_in(regex_def, [:captures], atomize_capture_keys(raw))

          nil ->
            acc
        end
    end
  end

  def parse_line(
        %{parser: %{match: %{context: context, captures: captures} = match}} =
          opts
      )
      when is_map(captures) do
    case context do
      :top_level -> opts |> handle_top_level(match)
      :base -> opts |> handle_base(match)
      :workers -> opts |> handle_workers(match)
      :cmd_definitions -> opts |> handle_cmd_def(match)
      :modes -> opts |> handle_mode(match)
      :steps -> opts |> handle_step(match)
      :actions -> opts |> handle_action(match)
      :unmatched -> opts |> handle_unmatched()
    end
  end

  # catchall to capture unmatched lines for syntax error reporting
  def handle_unmatched(%{parser: %{line: line, line_num: line_num}} = opts) do
    opts
    |> parser_metric_plus_one(:unmatched)
    |> parser_append_metric_line(:unmatched, {line_num, line})
  end

  # handle top_level lines
  # NOTE - new
  defp handle_top_level(
         %{parser: %{line_num: line_num}} = opts,
         %{stmt: stmt, context: _context, captures: captures}
       ) do
    case stmt do
      :comments ->
        comment = get_capture(captures, :comment)

        opts
        |> parser_metric_plus_one(:comments)
        |> parser_append_metric_line(:comments, comment)

      :section_def ->
        section = get_capture(captures, :section)

        opts
        |> parser_put_context(section)
        |> parser_track_section(section)
        |> config_put(section, %{})

      type when type in [:empties, :blanks] ->
        opts
        |> parser_metric_plus_one(type)
        |> parser_append_metric_line(type, line_num)
    end
  end

  # handle base section
  # NOTE - new
  defp handle_base(%{parser: %{context: parse_ctx}} = opts, %{
         stmt: stmt,
         context: match_ctx,
         captures: captures
       })
       when parse_ctx == :base and parse_ctx == match_ctx do
    case stmt do
      x when x in [:syntax_vsn, :timezone] ->
        opts |> update_in([:config, :base], fn x -> Map.merge(x, captures) end)

      _x ->
        config_put_kv(opts, [], captures)
    end
  end

  # handle workers section
  # NOTE - new
  defp handle_workers(%{parser: %{context: parse_ctx}} = opts, %{
         context: match_ctx,
         captures: captures
       })
       when parse_ctx == :workers and parse_ctx == match_ctx do
    opts |> config_put_kv([], captures)
  end

  # handle modes section
  # NOTE - new
  def handle_mode(%{parser: %{context: parse_ctx, modes: mode}} = opts, %{
        stmt: stmt,
        context: match_ctx,
        captures: captures
      })
      when parse_ctx in [:modes, :actions] do
    case stmt do
      :def ->
        opts
        |> parser_put(:modes, captures[:key])
        |> config_put([:modes, captures[:key]], %{})

      x when x in [:generic, :sequence] ->
        opts
        # we must ensure the parser context is reset to modes
        |> parser_put_context(match_ctx)
        |> config_put_kv([mode], captures)

      :steps ->
        section = captures[:key]

        opts
        |> parser_put_context(section)
        |> parser_track_section(section)
        |> config_put([:modes, mode, :steps], %{})

      _x ->
        opts
    end
  end

  # handle steps section
  # NOTE - new
  def handle_step(
        %{parser: %{context: parser_ctx, modes: mode}} = opts,
        %{stmt: stmt, context: match_ctx, captures: captures}
      )
      # NOTE:
      #  handle_step can be called in either the steps or actions context
      #  since it handles matching the first step definition and when a new step
      #  is defined when the list of actions ends
      when parser_ctx in [:steps, :actions] and match_ctx in [:steps, :actions] do
    case stmt do
      :basic ->
        opts
        |> parser_put(:steps, captures[:key])
        |> parser_put_context(:actions)
        |> parser_track_section(:actions)
        |> config_put([:modes, mode, :steps, captures[:key]], %{actions: []})

      :with_for ->
        opts
        |> parser_put(:steps, captures[:key])
        |> parser_put_context(:actions)
        |> parser_track_section(:actions)
        |> config_put([:modes, mode, :steps, captures[:key]], %{
          actions: [],
          run_for: captures[:val]
        })
    end
  end

  defp handle_action(
         %{parser: %{context: parser_ctx}} = opts,
         %{context: match_ctx}
       )
       when parser_ctx == :actions and parser_ctx == match_ctx do
    opts |> append_action()
  end

  defp handle_cmd_def(
         %{parser: %{context: parser_ctx, cmd_definitions: cmd_def}} = opts,
         %{
           stmt: stmt,
           context: match_ctx,
           captures: captures
         }
       )
       when parser_ctx == :cmd_definitions and match_ctx == parser_ctx do
    case stmt do
      :def ->
        opts
        |> parser_put(parser_ctx, captures[:key])
        |> config_put([match_ctx, captures[:key]], %{})

      :generic ->
        opts
        |> config_put([match_ctx, cmd_def, captures[:key]], captures[:val])

      :type ->
        opts
        |> config_put([match_ctx, cmd_def, :type], captures[:key])

      :key_val ->
        opts
        |> config_put_kv([cmd_def], captures)
    end
  end

  defp config_put_kv(%{parser: %{context: context}} = obj, path, %{
         key: key_atom,
         val: val
       }) do
    full_path = [:config, context, path, key_atom] |> List.flatten()

    obj |> put_in(full_path, val)
  end

  defp config_put(obj, path, val) do
    full_path = [:config, path] |> List.flatten()

    obj |> put_in(full_path, val)
  end

  # attempt to find the match regardless of if the full opts map or a
  # sub portion of it are passed
  defp get_capture(map, match_key) do
    get_in(map, [match_key]) ||
      get_in(map, [:captures, match_key]) ||
      get_in(map, [:match, :captures, match_key]) ||
      get_in(map, [:parser, :match, :captures, match_key])
  end

  defp parser_put(obj, path, val) do
    full_path = [:parser, [path]] |> List.flatten()

    obj |> put_in(full_path, val)
  end

  defp parser_put_captures(obj, path, val) do
    full_path = [:match, :captures, path] |> List.flatten()
    parser_put(obj, full_path, val)
  end

  defp parser_put_context(obj, context) do
    obj |> put_in([:parser, :context], context)
  end

  defp parser_track_section(opts, section) do
    opts |> put_in([:parser, section], nil)
  end

  defp parser_update_captures(opts, func) when is_function(func) do
    opts |> update_in([:parser, :match, :captures], fn x -> func.(x) end)
  end

  defp append_action(%{parser: %{modes: mode, steps: step, match: match}} = obj) do
    step_path = [:config, :modes, mode, :steps, step, :actions]

    obj
    |> update_in(step_path, fn x ->
      [x, [make_action(match)]] |> List.flatten()
    end)
  end

  defp parser_append_metric_line(obj, path, line) do
    full_path = [:parser, [path], :lines] |> List.flatten()

    obj |> update_in(full_path, fn x -> [x, line] |> List.flatten() end)
  end

  defp parser_metric_plus_one(obj, path) do
    full_path = [:parser, [path], :count] |> List.flatten()

    obj |> update_in(full_path, fn x -> x + 1 end)
  end

  defp make_action(%{stmt: stmt, captures: captures}) do
    case stmt do
      stmt when stmt in [:all, :sleep] ->
        # example: %{sleep: %Duration{}}
        %{cmd: captures[:key], worker: :self, args: captures[:val]}

      :cmd_basic ->
        %{
          cmd: captures[:cmd],
          worker: captures[:key],
          num_bin: captures[:number]
        }

      :cmd_list ->
        %{cmd: captures[:cmd], worker: captures[:val]}

      :cmd_for ->
        %{
          cmd: captures[:cmd],
          worker: captures[:key],
          for: captures[:iso8601],
          wait: captures[:nowait] != :nowait
        }

      x when x in [:cmd_for_then] ->
        %{
          cmd: captures[:cmd],
          worker: captures[:key],
          for: captures[:iso8601],
          at_cmd_finish: captures[:then_cmd],
          wait: captures[:nowait] != :nowait
        }

      :tell ->
        %{cmd: captures[:key], worker: captures[:worker], msg: captures[:msg]}
    end
    |> put_in([:stmt], stmt)
  end

  defp normalize_captures(
         %{parser: %{match: %{norm: norm, captures: captures}}} = opts
       )
       when norm in [:key_atom, :key_integer, :key_list, :key_iso8601] do
    import String, only: [to_integer: 1]

    case norm do
      :key_atom ->
        parser_put_captures(opts, [], atomize_capture_values(captures))

      :key_list ->
        parser_put_captures(opts, [:val], atomize_binary_list(captures[:val]))
        |> parser_update_captures(fn x -> atomize_capture_values(x) end)

      :key_integer ->
        parser_put_captures(opts, [:val], to_integer(captures[:val]))
        |> parser_update_captures(fn x -> atomize_capture_values(x) end)

      :key_iso8601 ->
        parser_put_captures(opts, [:val], to_duration(captures[:val]))
    end
  end

  # any unmatched norm kv is simply ignored
  defp normalize_captures(opts), do: opts

  defp atomize_binary_list(bin_list) do
    import String, only: [to_atom: 1, split: 2]

    for item_bin when is_binary(item_bin) <- split(bin_list, " "),
        do: to_atom(item_bin)
  end

  defp atomize_capture_keys(nil), do: nil

  defp atomize_capture_keys(map) do
    import String, only: [to_atom: 1]

    for {key_bin, val} <- map, reduce: map do
      acc ->
        # eliminate the original binary key and insert an atom key
        case key_bin do
          "key" ->
            # the values of "key" is always atomized
            Map.delete(acc, key_bin) |> put_in([to_atom(key_bin)], to_atom(val))

          _ ->
            Map.delete(acc, key_bin) |> put_in([to_atom(key_bin)], val)
        end
    end
  end

  defp atomize_capture_values(map) do
    import String, only: [to_atom: 1]

    for {key, val_bin} when is_binary(val_bin) <- map, reduce: map do
      acc ->
        cond do
          # any empty binaries (optional) are converted to nil
          val_bin == "" ->
            put_in(acc, [key], nil)

          # convert duration strings to internal %Duration{}
          key == :iso8601 ->
            put_in(acc, [key], to_duration(val_bin))

          # leave numbers (in binary form) unchanged
          key == :number ->
            acc

          is_binary(val_bin) ->
            # replace the binary value with an atomized value
            put_in(acc, [key], to_atom(val_bin))

          # anything else, do not attempt to atomize
          true ->
            acc
        end
    end
  end

  defp validate_syntax(%{parser: %{unmatched: unmatched}} = state) do
    case unmatched do
      %{lines: [], count: 0} -> put_in(state, [:syntax], :ok)
      _anything_else -> put_in(state, [:syntax], :error)
    end
  end

  defp log_errors(%{parser: %{log: false}} = opts), do: opts

  defp log_errors(%{parser: %{unmatched: %{lines: lines}}} = opts) do
    for {line_num, txt} <- lines do
      Logger.error(["unmatched: line ", Integer.to_string(line_num), ": ", txt])
    end

    opts
  end
end
