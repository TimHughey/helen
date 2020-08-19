defmodule Helen.Config.Parser.Regex do
  @moduledoc """
  Regex definitions for Config Parser
  """

  # credo:disable-for-next-line
  def re(what) do
    case what do
      :cmd ->
        "(?<cmd>(on|off))"

      :ident ->
        re(:ident, "ident")

      :iso8601 ->
        "(?<val>P(?:(0+)Y)?(?:(0+)M)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+(?:\\.\\d+)?)S)?)?)"

      :key ->
        "#{re(:key, :key)}"

      :key_cmd ->
        "(?<val>on|off)"

      :key_iso8601 ->
        "#{re(:key)}\\s+#{re(:iso8601)}"

      :key_list ->
        "#{re(:key)}\\s+#{re(:list)}"

      :key_quoted ->
        "#{re(:key)}\\s+#{re(:quoted_val)}"

      :kv ->
        "#{re(:key)}\\s+(?<val>[^\\x27]\\S+[^\\x27])"

      :nowait ->
        "(?:\\s+#{re(:key, :nowait)})?"

      :list ->
        "(?<val>[\\w\\d]+\\s+[\\w\\d\\s]+)"

      :quoted_val ->
        "\\x27(?<val>[a-zA-Z0-9\\s_\\x2d\\x2f]+)\\x27"
    end
  end

  def re(what, x) do
    x = Atom.to_string(x)

    case what do
      :cmd ->
        "(?<#{x}>(on|off))"

      :ident ->
        "(?<#{x}>[a-zA-Z]+[a-zA-Z0-9_]+)"

      :ident_quoted ->
        "#{re(:ident, x)}\\s+#{re(:quoted)}"

      :iso8601 ->
        "(?<#{x}>P(?:(0+)Y)?(?:(0+)M)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+(?:\\.\\d+)?)S)?)?)"

      :key ->
        "(?<#{x}>\\w+)"

      :key_match ->
        "(?<key>#{x})"

      :quoted ->
        # examples:
        #  syntax_vsn '2020-08-12'
        #  timezone 'America/New_York'
        "#{x}\\s+\\x27(?<#{x}>[a-zA-Z0-9\\s_\\x2d\\x2f]+)\\x27"
    end
  end

  def regex(regex_list) when is_list(regex_list) do
    for re <- List.flatten(regex_list), reduce: [] do
      list -> [list, regex(re)] |> List.flatten()
    end
  end

  # credo:disable-for-next-line
  def regex(what) when is_atom(what) do
    case what do
      :top_level ->
        [
          %{
            context: :top_level,
            stmt: :empties,
            norm: :key_binary,
            re: ~r/\A\z/
          },
          %{
            context: :top_level,
            stmt: :blanks,
            norm: :key_binary,
            re: ~r/^\s+$/
          },
          %{
            context: :top_level,
            stmt: :comments,
            norm: :key_binary,
            re: Regex.compile!("\\A#.(?<comment>.*)\\z")
          },
          %{
            context: :top_level,
            stmt: :section_def,
            norm: :key_atom,
            re: Regex.compile!("^#{ident("section")}$")
          }
        ]

      :base ->
        [
          %{
            context: :base,
            stmt: :syntax_vsn,
            norm: :key_quoted,
            re: Regex.compile!("^\\s{2}#{re(:quoted, :syntax_vsn)}$")
          },
          %{
            context: :base,
            stmt: :timeout,
            norm: :key_iso8601,
            re: Regex.compile!("^\\s{2}#{re(:key_iso8601)}$")
          },
          %{
            context: :base,
            stmt: :timezone,
            norm: :key_quoted,
            re: Regex.compile!("^\\s{2}#{re(:quoted, :timezone)}$")
          },
          %{
            context: :base,
            stmt: :generic,
            norm: :key_atom,
            re: Regex.compile!("^\\s{2}#{re(:kv)}$")
          }
        ]

      :devices ->
        [
          %{
            context: :devices,
            stmt: :def_quoted,
            norm: :key_quoted,
            re: Regex.compile!("^\\s{2}#{re(:key_quoted)}$")
          },
          %{
            context: :devices,
            stmt: :def_atom,
            norm: :key_atom,
            re: Regex.compile!("^\\s{2}#{re(:kv)}$")
          }
        ]

      :modes ->
        [
          %{
            context: :modes,
            stmt: :def,
            norm: :key,
            re: Regex.compile!("^\\s{2}#{re(:key)}$")
          },
          %{
            context: :modes,
            stmt: :generic,
            norm: :key_atom,
            re: Regex.compile!("^\\s{4}#{re(:kv)}$")
          },
          %{
            context: :modes,
            stmt: :sequence,
            norm: :key_list,
            re: Regex.compile!("^\\s{4}#{re(:key_list)}$")
          },
          %{
            context: :modes,
            stmt: :steps,
            norm: :key,
            re: Regex.compile!("^\\s{4}#{re(:key)}$")
          }
        ]

      :steps ->
        [
          %{
            context: :steps,
            stmt: :basic,
            norm: :key,
            re: Regex.compile!("^\\s{6}#{re(:key)}$")
          },
          %{
            context: :steps,
            stmt: :with_for,
            norm: :key_iso8601,
            re: Regex.compile!("^\\s{6}#{re(:key)}\\s+for\\s+#{re(:iso8601)}")
          }
        ]

      :actions ->
        [
          %{
            context: :actions,
            stmt: :sleep,
            norm: :key_iso8601,
            re: Regex.compile!("^\\s{8}#{re(:key_iso8601)}$")
          },
          %{
            context: :actions,
            stmt: :tell,
            norm: :key_atom,
            re:
              Regex.compile!(
                "^\\s{8}#{re(:key_match, :tell)}\\s+#{re(:key, :device)}\\s+#{
                  re(:key, :msg)
                }$"
              )
          },
          %{
            context: :actions,
            stmt: :all,
            norm: :key_atom,
            re:
              Regex.compile!(
                "^\\s{8}#{re(:key_match, :all)}\\s+#{re(:key_cmd)}$"
              )
          },
          %{
            context: :actions,
            stmt: :dev_cmd_basic,
            norm: :key_atom,
            re: Regex.compile!("^\\s{8}#{re(:ident, :key)}\\s+#{re(:cmd)}$")
          },
          %{
            context: :actions,
            stmt: :dev_cmd_for,
            norm: :key_atom,
            re:
              Regex.compile!(
                "^\\s{8}#{re(:ident, :key)}\\s+#{re(:cmd)}\\s+#{
                  re(:iso8601, :iso8601)
                }#{re(:nowait)}$"
              )
          },
          %{
            context: :actions,
            stmt: :dev_cmd_for_then,
            norm: :key_atom,
            re:
              Regex.compile!(
                "^\\s{8}#{re(:ident, :key)}\\s+#{re(:cmd)}\\s+#{
                  re(:iso8601, :iso8601)
                }\\s+then\\s+#{re(:cmd, :then_cmd)}#{re(:nowait)}$"
              )
          }
        ]

      :cmd_defs ->
        [
          %{
            context: :cmd_defs,
            stmt: :def,
            norm: :key,
            re: Regex.compile!("^\\s{2}#{re(:key)}$")
          },
          %{
            # example:
            # name 'fade bright'
            context: :cmd_defs,
            stmt: :generic,
            norm: :key_quoted,
            re: Regex.compile!("^\\s{4}#{re(:key_quoted)}$")
          }
        ]

      :end_of_list ->
        [
          %{
            context: :unmatched,
            stmt: :unmatched,
            norm: :unmatched,
            re: Regex.compile!("^.*$")
          }
        ]
    end
  end

  defp ident(ident), do: "(?<#{ident}>[a-zA-Z]+[a-zA-Z0-9_]+)"

  # def regex(:action) do
  #   dev_cmd_then = "#{dev_cmd_for}\\s+then\\s+(?<then_cmd>(on|off))"
  #   dev_cmd_nowait = "#{dev_cmd_then}\\s+nowait"
  #
  #   [
  #     {:action, :dev_cmd_then, Regex.compile!("#{dev_cmd_then}$")},
  #     {:action, :dev_cmd_nowait, Regex.compile!("#{dev_cmd_nowait}$")}
  #   ]
  # end
  #
end
