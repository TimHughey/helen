defmodule Remote.Fact do
  @moduledoc """
    Specific processing for Remote messages
  """

  alias Remote.DB.Remote, as: Remote

  # handle temperature metrics

  # this function will always return a tuple:
  #  a. {:processed, :ok} -- metric was written
  #  c. {:processed, :no_match} -- metric not written, error condition
  def write_specific_metric(
        %Remote{} = x,
        %{
          write_rc: nil,
          remote_host: {:ok, %Remote{host: host, name: name}},
          msg_recv_dt: recv_dt,
          type: "boot"
        } = _msg
      ) do
    import Fact.Influx, only: [write: 2]

    # assemble the metric fields
    fields =
      Map.take(x, [
        :reset_reason
      ])
      |> Enum.reject(fn
        {_k, v} when is_nil(v) -> true
        {_k, _v} -> false
      end)
      |> Enum.into(%{boot: 1})

    {:processed,
     %{
       points: [
         %{
           measurement: "remote",
           fields: fields,
           tags: %{host: host, name: name},
           timestamp: DateTime.to_unix(recv_dt, :nanosecond)
         }
       ]
     }
     |> write(precision: :nanosecond, async: true)}
  end

  # if this wasn't a boot message then it's :ok, nothing to write
  def write_specific_metric(
        %Remote{},
        %{write_rc: nil, remote_host: {:ok, %Remote{}}} = _msg
      ) do
    {:processed, :ok}
  end

  def write_specific_metric(_datapoint, _msg) do
    {:processed, :no_match}
  end
end
