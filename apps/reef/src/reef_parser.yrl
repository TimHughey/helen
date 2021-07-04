Nonterminals sections section section_item section_items
mode_items mode_item
actions action
cmd_rnd_details cmd_rnd_detail
ident_list.

Terminals '{' '}' ',' section_def section_kw mode step for then nowait tell
  sleep duty number ident next_mode sequence string duration
  command random cmd_random_kw
  worker_cmd worker_wildcard.

Rootsymbol sections.

sections ->
  section : ['$1' | []].

sections ->
  section sections : [ '$1' | '$2' ].

section ->
  section_def '{' section_items '}' : {value('$1'), '$3'}.

section ->
  mode ident '{' mode_items '}' :
    {mode, #{name => value('$2'), details => '$4'}}.

section ->
  command ident string random '{' cmd_rnd_details '}' :
    {value('$1'), #{cmd => value('$2'), name => value('$3'),
      type => value('$4'), details => '$6'}}.

section_items ->
  section_item : ['$1' | []].

section_items ->
  section_item section_items : [ '$1' | '$2'].

section_item ->
  section_kw duration : make_keyword('$1', '$2').

section_item ->
  % section_kw string : [value('$1'), value('$2')].
  section_kw string : make_keyword('$1', '$2').

section_item ->
  section_kw ident : make_keyword('$1', '$2').

section_item ->
  ident string : make_keyword('$1', '$2').

mode_items ->
  mode_item : ['$1' | []].

mode_items ->
  mode_item mode_items : [ '$1' | '$2'].

mode_item ->
  next_mode ident : make_keyword('$1', '$2').

mode_item ->
  sequence ident_list : make_keyword('$1', '$2').

mode_item ->
  step ident for duration '{' actions '}' :
    {step, #{name => value('$2'), for => value('$4'), actions => '$6'}}.

mode_item ->
  step ident '{' actions '}' :
    {step, #{name => value('$2'), actions => '$4'}}.

actions ->
  action : ['$1' | []].

actions ->
  action actions : [ '$1' | '$2'].

action ->
  worker_wildcard worker_cmd :
    #{worker_name => value('$1'), cmd => value('$2')}.

action ->
  worker_cmd ident_list :
    #{cmd => value('$1'), worker_name => '$2'}.

action ->
  tell ident ident :
    #{cmd => value('$1'), worker_name => value('$2'), mode => value('$3')}.

action ->
  sleep duration :
    #{cmd => value('$1'), worker_name => nil, for => value('$2')}.

action ->
  ident worker_cmd for duration then worker_cmd nowait :
    #{worker_name => value('$1'), cmd => value('$2'),
      for => value('$4'), then => value('$6'), nowait => true}.

action ->
  ident worker_cmd for duration then worker_cmd :
    #{worker_name => value('$1'), cmd => value('$2'),
      for => value('$4'), then => value('$6')}.

action ->
  ident worker_cmd for duration :
    #{worker_name => value('$1'), cmd => value('$2'),
      for => value('$4')}.

action ->
  ident duty number :
    #{worker_name => value('$1'), cmd => value('$2'), number => value('$3')}.

action ->
  ident worker_cmd :
    #{worker_name => value('$1'), cmd => value('$2')}.

action ->
  ident ident :
    #{worker_name => value('$1'), cmd => value('$2')}.

ident_list ->
  ident : [ value('$1') | []].

ident_list ->
  ident ',' ident_list : [ value('$1') | '$3' ].

cmd_rnd_details ->
  cmd_rnd_detail : ['$1' | []].

cmd_rnd_details ->
  cmd_rnd_detail ',' cmd_rnd_details : [ '$1' | '$3'].

cmd_rnd_detail ->
  cmd_random_kw number : {value('$1'), value('$2')}.

% SPECIAL CASE:
% step is defined as a pure atom for step definitions so we must direct match
cmd_rnd_detail ->
  step number : {value('$1'), value('$2')}.

Erlang code.

% make_type_tuple({_, _, Key}, {Type, _, Value}) ->
%   {Key, {Type, Value}}.

make_keyword(KeyTuple, ValueTuple) ->
 {case KeyTuple of
    {_, _, Key} -> Key;
    {Key, _} -> Key;
    Key -> Key
  end,
  case ValueTuple of
    {_, _, Val} -> Val;
    {Val, _} -> Val;
    Val -> Val
  end}.



value(Tuple) ->
  case Tuple of
    {_, _, Value} -> Value;
    {Value, _} -> Value
  end.
