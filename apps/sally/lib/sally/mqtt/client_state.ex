defmodule Sally.Mqtt.Client.State do
  defstruct client_id: nil,
            connected: false,
            runtime_metrics: false,
            last_pub: nil

  @type pub_elapsed_us() :: pos_integer()
  @type tort_rc() :: {:ok, reference()}
  @type last_pub() :: {pub_elapsed_us(), tort_rc()}

  @type t :: %__MODULE__{
          client_id: String.t(),
          connected: boolean(),
          runtime_metrics: boolean(),
          last_pub: last_pub()
        }
end
