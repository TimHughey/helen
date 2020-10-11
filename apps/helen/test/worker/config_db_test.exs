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

    opts = Config.find_opts(module: "This.Is.A.Module", version: 1)
    assert opts == [module: "This.Is.A.Module"]
  end

  test "find returns :not_found when a config does not exist" do
    assert Config.find("Foo.Bar") == []
  end

  test "can detect invalid find opts" do
    assert {:bad_args, 1234} == Config.find(1234)
  end

  test "can insert a module config without lines" do
    {rc, cfg} = Config.insert(module: "No.Lines.Module")

    assert rc == :ok
    assert %_{lines: lines, comment: comment} = cfg
    assert lines == []
    assert comment == "<none>"
  end

  test "can save a module config" do
    alias Helen.Worker.Config

    snippet = """
    base {
      timeout PT5M
      timezone "America/New_York"
    }
    """

    res = Config.save("With.Lines.Module", snippet)

    assert %{db: :ok, count: count} = res
    assert count == 5
  end

  test "can save and find a module config" do
    alias Helen.Worker.Config

    snippet = """
    base {
      timeout PT5M
      timezone "America/New_York"
    }
    """

    res = Config.save(Save.And.Find.Module, snippet)

    assert %{db: :ok, count: count} = res
    assert count == 5

    found = Config.get(:latest, Save.And.Find.Module, "")

    assert {:ok, _binary} = found
  end

  test "can find a module config with two version" do
    alias Helen.Worker.Config

    snippet1 = """
    base {
      timeout PT5M
      timezone "America/New_York"
    }
    """

    snippet2 = """
    base {
      timeout PT1M
      timezone "America/New_York"
    }
    """

    res1 = Config.save(Multiple.Config.Module, snippet1)
    res2 = Config.save(Multiple.Config.Module, snippet2)

    assert %{db: :ok, count: _} = res1
    assert %{db: :ok, count: _} = res2

    found1 = Config.get(:latest, Multiple.Config.Module, "")
    found2 = Config.get(:previous, Multiple.Config.Module, "")

    assert {:ok, _binary} = found1
    assert {:ok, _binary} = found2
  end
end
