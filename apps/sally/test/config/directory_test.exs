defmodule SallyConfigDirectoryTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_config_directory: true

  describe "Sally.Config.Directory.discover/1" do
    test "returns a path when a dir exists" do
      refute :none == Sally.Config.Directory.discover({__MODULE__, :host_profiles})
    end

    test "returns :none when dir not found" do
      assert :none = Sally.Config.Directory.discover({__MODULE__, :not_a_key})
    end
  end

  describe "Sally.Config.Directory.search/2" do
    @tag :tmp_dir
    test "finds a directory using search absolute paths", %{tmp_dir: tmp_dir} do
      expected_path = Path.join(tmp_dir, "foo")
      assert :ok == File.mkdir(expected_path)

      assert expected_path == Sally.Config.Directory.search("foo", [tmp_dir])
    end
  end
end
