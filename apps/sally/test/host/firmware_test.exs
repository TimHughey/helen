defmodule Sally.HostFirmwareTest do
  # NOTE:  don't use async: true due to testing Sally.host_setup(:unnamed)
  use ExUnit.Case
  use Should

  alias Sally.Host.Firmware

  @moduletag sally: true, sally_host_firmware: true

  describe "Sally.Host.Firmware.find_dir/1" do
    test "finds firmware dir in cwd (empty opts)" do
      Firmware.find_dir([])
      |> Should.Be.binary()
    end
  end

  describe "Sally.Host.Firmware.available/1" do
    test "gets a list of files from a directory" do
      opts = Firmware.assemble_opts([])

      Firmware.available("./firmware", opts)
      |> Should.Be.List.of_binaries()
    end
  end

  describe "Sally.Host.Firmware.select_file/1" do
    test "returns latest file by default" do
      opts = Firmware.assemble_opts([])

      Firmware.available("./firmware", opts)
      |> Firmware.select_file(:latest)
      |> Should.Be.binary()
    end
  end
end
