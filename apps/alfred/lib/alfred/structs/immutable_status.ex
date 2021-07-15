defmodule Alfred.ImmutableStatus do
  alias __MODULE__, as: Status

  defstruct name: nil,
            good?: false,
            found?: true,
            datapoints: nil,
            status_at: nil,
            ttl_expired?: false,
            error: :none

  @type status_error() :: :none | :unresponsive | :unknown_value
  @type t :: %__MODULE__{
          name: String.t(),
          good?: boolean(),
          found?: boolean(),
          datapoints: %{temp_c: float(), temp_f: float(), relhum: float() | nil} | %{},
          status_at: DateTime.t(),
          ttl_expired?: boolean(),
          error: status_error()
        }

  def add_datapoint(%Status{} = status, key, val) do
    %Status{status | datapoints: status.datapoints |> put_in([key], val)}
  end

  def diff(key, %Status{datapoints: dp1, good?: true}, %Status{datapoints: dp2, good?: true})
      when is_atom(key) and is_map_key(dp1, key) and is_map_key(dp2, key) do
    v1 = dp1[key]
    v2 = dp2[key]

    if is_number(v1) and is_number(v2) do
      v1 - v2
    else
      :error
    end
  end

  def diff(_key, _status1, _status2), do: :error

  # (1 of 2) this status is good: ttl is ok, it is found and no error
  def finalize(%Status{error: :none, found?: true, ttl_expired?: false} = x) do
    %Status{x | good?: true}
  end

  # (2 of 2) something is wrong with this status
  def finalize(%Status{} = x), do: x

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
