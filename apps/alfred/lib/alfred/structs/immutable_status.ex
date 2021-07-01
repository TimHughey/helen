defmodule Alfred.ImmutableStatus do
  alias __MODULE__, as: Status

  defstruct name: nil,
            found?: true,
            datapoints: nil,
            status_at: nil,
            ttl_expired?: false,
            error: :none

  @type status_error() :: :none | :unresponsive | :unknown_value
  @type t :: %__MODULE__{
          name: String.t(),
          found?: boolean(),
          datapoints: %{temp_c: float(), relhum: float() | nil} | %{},
          status_at: DateTime.t(),
          ttl_expired?: boolean(),
          error: status_error()
        }

  def good(%_{datapoints: [values_map]} = x) do
    %Status{
      name: x.name,
      datapoints: values_map,
      status_at: x.device.last_seen_at
    }
  end

  def not_found(name), do: %Status{name: name, status_at: DateTime.utc_now(), found?: false}

  def ttl_expired(%_{} = x) do
    %Status{name: x.name, status_at: x.device.last_seen_at, ttl_expired?: true}
  end

  def tty_expired?(%Status{ttl_expired?: expired}), do: expired

  def unknown_status(%_{} = x) do
    %Status{
      name: x.name,
      datapoints: %{},
      status_at: x.updated_at,
      error: :no_datapoints
    }
  end
end
