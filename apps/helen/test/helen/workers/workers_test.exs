defmodule HelenWorkersTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  alias Helen.Workers

  setup_all do
    dev_map = %{
      air: "mixtank air",
      pump: "mixtank pump",
      mixtank_temp: "mixtank heater",
      foobar: "foo bar"
    }

    %{wc: Workers.build_module_cache(dev_map)}
  end

  setup do
    %{token: make_ref()}
  end

  test "can build workers module cache from a map of workers", %{wc: res} do
    assert is_map(res)

    for ident <- [:air, :pump, :mixtank_temp] do
      assert res[ident][:found?]
    end

    assert res[:air][:type] == :gen_device

    refute res[:foobar][:found?]

    refute Workers.module_cache_complete?(res)
  end

  test "can resolve a simple worker atom", %{wc: wc} do
    res = Workers.resolve_worker(wc, :air)

    assert res == get_in(wc, [:air])
  end

  test "can resolve a list of workers", %{wc: wc} do
    res = Workers.resolve_worker(wc, [:air, :pump])

    assert res == [get_in(wc, [:air]), get_in(wc, [:pump])]
  end

  test "can execute a sleep action", %{wc: wc, token: token} do
    import Helen.Time.Helper, only: [to_duration: 1]

    action =
      Workers.make_action(
        :test,
        wc,
        %{stmt: :sleep, cmd: :sleep, args: to_duration("PT0.001S")},
        %{token: token}
      )

    res = Workers.execute_action(action)

    assert res[:stmt] == :sleep
    assert res[:via_msg]
    assert is_reference(res[:action_ref])
    assert is_reference(res[:result])

    assert_receive {:test, %{cmd: :sleep, token: ^token}}, 100
  end

  # test "can execute the 'tell' action", %{wc: wc, token:} do
  #   alias Reef.Captain.Server, as: Captain
  #
  #
  # end

  test "the truth will set you free" do
    assert true
  end
end
