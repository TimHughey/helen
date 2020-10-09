defmodule HelenWorkerConfigDBTest do
  @moduledoc false

  alias Helen.Worker.Config.DB.Config

  use ExUnit.Case

  @moduletag :worker_config_db

  setup_all do
    %{}
  end

  setup context do
    context
  end

  test "can build find opts" do
    opts = Config.find_opts(module: "This.Is.A.Module", version: :latest)
    assert opts == [module: "This.Is.A.Module"]

    opts = Config.find_opts(module: This.Is.A.Module)
    assert opts == [module: "This.Is.A.Module"]

    opts = Config.find_opts(module: "This.Is.A.Module", version: "2020-1001")
    assert opts == [module: "This.Is.A.Module", version: "2020-1001"]
  end

  test "find returns nil when a config does not exist" do
    assert is_nil(Config.find("Foo.Bar"))
  end

  test "can detect invalid find opts" do
    assert {:bad_args, [module: 1234, version: :latest]} == Config.find(1234)
  end
end
