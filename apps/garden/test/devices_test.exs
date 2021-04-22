defmodule DevicesTest do
  use ExUnit.Case, async: true

  @moduletag :devices

  import GardenTestHelpers, only: [make_state: 1, pretty: 1]

  def setup_ctx(args) do
    {rc, s} = make_state(args)

    assert :ok == rc, "state creation failed#{pretty(s)}"

    %{state: s, ctrl_maps: Lights.ControlMap.make_control_maps(s)}
  end

  setup ctx do
    args = get_in(ctx, [:state_args]) || :default

    {:ok, setup_ctx(args)}
  end

  test "can detect a device exists", %{ctrl_maps: cm} do
    for {:device, name} when is_binary(name) <- cm do
      assert Lights.Devices.exists?(name) == true, "unable to find #{name}"
    end
  end

  test "can detect a device does not exist" do
    refute Lights.Devices.exists?("this does not exist")
  end
end
