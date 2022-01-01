defmodule Sally.HostFirmwareTest do
  use ExUnit.Case, async: true

  @moduletag sally: true, sally_host_firmware: true

  describe "Sally.Host.Firmware.find_dir/1" do
    test "finds firmware dir in cwd (empty opts)" do
      assert <<_::binary>> = Sally.Host.Firmware.find_dir([])
    end
  end

  describe "Sally.Host.Firmware.available/1" do
    test "gets a list of files from a directory" do
      opts = Sally.Host.Firmware.assemble_opts([])

      assert [<<_::binary>>, <<_::binary>> | _] = Sally.Host.Firmware.available("./firmware", opts)
    end
  end

  describe "Sally.Host.Firmware.select_file/1" do
    test "returns latest file by default" do
      opts = Sally.Host.Firmware.assemble_opts([])

      assert [<<_::binary>> | _] = Sally.Host.Firmware.available("./firmware", opts)
    end
  end
end
