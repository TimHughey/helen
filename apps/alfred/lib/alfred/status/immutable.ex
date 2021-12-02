defmodule Alfred.ImmutableStatus do
  alias __MODULE__, as: Status

  @derive [Alfred.Status]
  defstruct name: nil,
            good?: false,
            found?: true,
            datapoints: nil,
            status_at: nil,
            ttl_expired?: false,
            error: :none

  @type datapoints :: %{optional(:temp_c) => float, optional(:temp_c) => float, optional(:temp_f) => float}
  @type status_error() :: :none | :unresponsive | :unknown_value

  @type t :: %Status{
          name: String.t(),
          good?: boolean(),
          found?: boolean(),
          datapoints: datapoints() | %{},
          status_at: DateTime.t(),
          ttl_expired?: boolean(),
          error: status_error()
        }

  def add_datapoint(%Status{} = status, key, val) do
    %Status{status | datapoints: status.datapoints |> put_in([key], val)}
  end

  # (1 of 3) diff of two ImmutableStatus structs
  @doc """
  Calculate the difference of a specified key of an ImmutableStatus and numberic value or
  another ImmutableStatus.

  """
  @doc since: "0.0.1"
  def diff(key, %Status{datapoints: dp1, good?: true}, %Status{datapoints: dp2, good?: true})
      when is_atom(key) and is_map_key(dp1, key) and is_map_key(dp2, key) do
    val1 = dp1[key]
    val2 = dp2[key]

    if is_number(val1) and is_number(val2) do
      val1 - val2
    else
      :error
    end
  end

  # (2 of 3) diff of a numeric value and the specified key of an ImmutableStatus
  def diff(key, val1, %Status{datapoints: dp, good?: true})
      when is_atom(key) and is_map_key(dp, key) and is_number(val1) do
    val2 = dp[key]

    if is_number(val2) do
      val1 - val2
    else
      :error
    end
  end

  # (3 of 3) key doesn't exist, can't compare passed arguments or bad status
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

  def not_found(name) do
    %Status{name: name, status_at: DateTime.utc_now(), found?: false, error: :not_found}
  end

  def ttl_expired(%_{} = x) do
    %Status{name: x.name, status_at: x.device.last_seen_at, ttl_expired?: true}
  end

  def ttl_expired?(%Status{ttl_expired?: expired}), do: expired

  def unknown_status(%_{} = x) do
    %Status{
      name: x.name,
      datapoints: %{},
      status_at: x.updated_at,
      error: :no_datapoints
    }
  end
end
