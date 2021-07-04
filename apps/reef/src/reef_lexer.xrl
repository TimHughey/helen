Definitions.

COMMENT=#[\s\t]+.*[\r\n]
SECTIONS=base|workers
MODE=mode
% ALL=all[\s\t\r\n]
FOR=for
STEP=step
THEN=then
NOWAIT=nowait
TELL=tell
SLEEP=sleep
SECTION_KEYWORDS=syntax_vsn|worker_name|description|timeout|timezone|first_mode|start_mode|config_vsn
MODE_META=next_mode|sequence
WHITESPACE=[\s\t\r\n;]+
STRING="[^\"]+"
SYMBOLS=[{},]
IDENT=[a-zA-Z][a-zA-Z0-9_-]+
WORKER_WILDCARD=all
ON_OFF=(on|off)
DUTY=duty
FLOAT=[-+]?[0-9]+\.[0-9]+
INTEGER=[-+]?[0-9]+
CMD_RANDOM_KEYWORDS=min|max|primes|step_ms|step_inc|priority
COMMAND=command
RANDOM=random

% Durations
D_MTH_DAY=P(([0-9]+M[0-9]+D)|([0-9]+M))
D_HR=PT[0-9]+H
D_HR_MIN=PT[0-9]+H[0-9]+M
D_MIN=PT[0-9]+M
D_MIN_SEC=PT[0-9]+M[0-9]+S
D_SEC=PT[0-9]+S
D_SEC_MS=PT[0-9]+\.[0-9][0-9]?[0-9]?S

Rules.

{WHITESPACE} : skip_token.
{COMMENT} : skip_token.
{SYMBOLS} : {token, {list_to_atom(TokenChars), TokenLine}}.
{STRING} : {token, {string, TokenLine, extract_string(TokenChars)}}.
{D_MTH_DAY} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{D_HR} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{D_HR_MIN} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{D_MIN} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{D_MIN_SEC} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{D_SEC} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{D_SEC_MS} : {token, {duration, TokenLine, list_to_binary(TokenChars)}}.
{MODE} : {token, {list_to_atom(TokenChars), TokenLine}}.
{FOR} : {token, {list_to_atom(TokenChars), TokenLine}}.
{STEP} : {token, {list_to_atom(TokenChars), TokenLine}}.
{TELL} : {token, {list_to_atom(TokenChars), TokenLine}}.
{THEN} : {token, {list_to_atom(TokenChars), TokenLine}}.
{NOWAIT} : {token, {list_to_atom(TokenChars), TokenLine}}.
{SLEEP} : {token, {list_to_atom(TokenChars), TokenLine}}.
{DUTY} : {token, {list_to_atom(TokenChars), TokenLine}}.
{RANDOM} : {token, {list_to_atom(TokenChars), TokenLine}}.
{FLOAT} : {token, {number, TokenLine, list_to_float(TokenChars)}}.
{INTEGER} : {token, {number, TokenLine, list_to_integer(TokenChars)}}.
{MODE_META} : {token, {list_to_atom(TokenChars), TokenLine}}.
{SECTIONS} : {token, {section_def, TokenLine, list_to_atom(TokenChars)}}.
{SECTION_KEYWORDS} : {token, {section_kw, TokenLine, list_to_atom(TokenChars)}}.
{ON_OFF} : {token, {worker_cmd, TokenLine, list_to_atom(TokenChars)}}.
{WORKER_WILDCARD} : {token, {worker_wildcard, TokenLine, list_to_atom(TokenChars)}}.
{COMMAND} : {token, {list_to_atom(TokenChars), TokenLine}}.
{CMD_RANDOM_KEYWORDS} : {token, {cmd_random_kw, TokenLine, list_to_atom(TokenChars)}}.

% must remain last to avoid matching reserved words
{IDENT} : {token, {ident, TokenLine, list_to_atom(TokenChars)}}.

Erlang code.

% extract_number(Chars) ->
%   HasDot = lists:member(".", Chars),
%
%     if
%       HasDot == true ->
%         list_to_float(Chars);
%
%       true ->
%         list_to_integer(Chars)
%     end.


extract_string(Chars) ->
    list_to_binary(lists:sublist(Chars, 2, length(Chars) - 2)).
