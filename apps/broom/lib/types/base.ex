defmodule Broom.BaseTypes do
  @type datetime_or_nil() :: DateTime.t() | nil
  @type db_primary_id() :: pos_integer() | nil
  @type db_result() :: {:ok, Echo.Schema.t()} | {:error, any()} | nil
  @type iso8601_duration() :: String.t()
  @type milliseconds_or_nil :: pos_integer() | nil
  @type module_or_nil() :: module() | nil
  @type track_opts() :: %{timeout: iso8601_duration(), max_history: list()}
  @type pid_or_nil() :: pid() | nil
  @type rc() :: :never | nil | term
  @type reference_or_nil() :: reference() | nil
  @type refid() :: String.t() | pos_integer()
  @type schema_or_nil() :: Ecto.Schema.t() | nil
  @type server_info_map() :: %{
          id: module_or_nil(),
          name: module_or_nil(),
          genserver: [] | keyword()
        }
end
