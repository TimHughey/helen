defmodule Helen.Config.Parser do
  @moduledoc """
  Parses configuration text files
  """

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
      two_spaces = "  "

      String.replace(line, "\t", two_spaces)
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
        |> debug_opts()
        |> match_line()
        |> debug_opts()
        |> normalize_captures()
        |> debug_opts()
        # |> debug_match()
        # |> debug_captures()
        |> parse_line()
        |> debug_opts()
    end
  end

  def debug_opts(opts) do
    # IO.puts("debug_opts: #{inspect(opts, pretty: true)}")
    opts
  end

  # def debug_match(
  #       %{
  #         parser: %{
  #           match: {_, _, captures} = match,
  #           line: line,
  #           line_num: line_num
  #         }
  #       } = opts
  #     ) do
  #   [
  #     "line_num: ",
  #     Integer.to_string(line_num),
  #     " ",
  #     inspect(line, pretty: true),
  #     " ",
  #     inspect(match, pretty: true)
  #   ]
  #   |> IO.puts()
  #
  #   opts
  # end

  def debug_match(opts), do: opts

  # detect, count and track skipped lines
  #   (e.g. empty, only white space, comments)

  def debug_captures(opts), do: opts

  def match_line(%{parser: %{context: context, line: line}} = opts) do
    opts |> put_in([:parser, :match], run_regex(context, line))
  end

  @doc false
  # determine what regex to match based on the current context
  def regex_list(context) do
    case context do
      :top_level ->
        regex([:top_level, :end_of_list])

      x when x in [:base, :devices, :modes, :steps] ->
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
      :devices -> opts |> handle_devices(match)
      :cmds -> opts |> handle_cmd_def(match)
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

  # handle devices section
  # NOTE - new
  defp handle_devices(%{parser: %{context: parse_ctx}} = opts, %{
         context: match_ctx,
         captures: captures
       })
       when parse_ctx == :devices and parse_ctx == match_ctx do
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

  defp handle_cmd_def(opts, {section, :def, %{key: key_atom}})
       when section == :cmds do
    opts
    |> parser_put(:section, key_atom)
    |> parser_put(section, key_atom)
    |> config_put([section, key_atom], %{})
  end

  defp handle_cmd_def(
         %{parser: %{cmds: cmds}} = opts,
         {section, type, %{key: key_atom, val: val}}
       )
       when section == :cmds do
    case type do
      type when type in [:kq, :kv] ->
        opts |> config_put([section, cmds, key_atom], val)

      _anything ->
        opts
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

  defp append_action(%{parser: %{modes: mode, steps: step, match: match}} = obj) do
    step_path = [:config, :modes, mode, :steps, step, :actions]

    obj
    |> update_in(step_path, fn x ->
      [x, make_action(match)] |> List.flatten()
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
        %{captures[:key] => captures[:val]}

      :dev_cmd_basic ->
        %{device: captures[:key], cmd: captures[:cmd]}

      :dev_cmd_for ->
        %{
          device: captures[:key],
          cmd: captures[:cmd],
          for: captures[:iso8601],
          wait: captures[:nowait] != :nowait
        }

      x when x in [:dev_cmd_for_then] ->
        %{
          device: captures[:key],
          cmd: captures[:cmd],
          for: captures[:iso8601],
          then_cmd: captures[:then_cmd],
          wait: captures[:nowait] != :nowait
        }

      :tell ->
        %{captures[:key] => %{device: captures[:device], msg: captures[:msg]}}
    end
  end

  defp validate_device(
         %{parser: %{line_num: line_num}, config: %{devices: devices}} = opts,
         dev
       ) do
    if Map.has_key?(devices, dev) do
      opts
    else
      opts |> record_error(line_num, "device #{dev} is not defined")
    end
  end

  defp record_error(opts, line_num, error) do
    text = "line #{Integer.to_string(line_num)} #{error}"

    opts
    |> update_in([:parser, :errors], fn x -> [x, text] |> List.flatten() end)
  end

  defp normalize_captures(
         %{parser: %{match: %{norm: norm, captures: captures}}} = opts
       )
       when norm in [:key_atom, :key_list, :key_iso8601] do
    case norm do
      :key_atom ->
        parser_put_captures(opts, [], atomize_capture_values(captures))

      :key_list ->
        parser_put_captures(opts, [:val], atomize_binary_list(captures[:val]))

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
            # "key" is always atomized
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
        if key == :iso8601 do
          put_in(acc, [key], to_duration(val_bin))
        else
          # replace the binary value with an atomized value
          put_in(acc, [key], to_atom(val_bin))
        end
    end
  end
end
