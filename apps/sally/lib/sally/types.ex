defmodule Sally.Types do
  @type child_spec_opts() :: map() | keyword()
  @type datetime_or_nil() :: DateTime.t() | nil
  @type device_or_remote_identifier() :: String.t()
  @type db_primary_id() :: pos_integer() | nil
  @type db_result() :: {:ok, Echo.Schema.t()} | {:error, any()} | nil
  @type iso8601_duration() :: String.t()
  @type milliseconds_or_nil :: pos_integer() | nil
  @type module_or_nil() :: module() | nil
  @type msg_env() :: String.t() | nil
  @type msg_in_type() :: String.t()
  @type track_opts() :: %{timeout: iso8601_duration(), max_history: list()}
  @type payload() :: nil | bitstring() | :unpacked
  @type pub_data() :: map()
  @type pub_to_device() :: Ecto.Schema.t()
  @type pub_topic_filters() :: nonempty_list()
  @type pid_or_nil() :: pid() | nil
  @type pub_rc() :: reference() | nil
  @type rc() :: :never | nil | term
  @type reference_or_nil() :: reference() | nil
  @type refid() :: String.t()
  @type schema_or_nil() :: Ecto.Schema.t() | nil
  @type server_info_map() :: %{
          id: module_or_nil(),
          name: module_or_nil(),
          genserver: [] | keyword()
        }
end
