defmodule RemoteProfileTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Remote.Profile
  alias Remote.Profile.Schema

  @moduletag :remote_profile

  test "can create a Remote Profile with default values" do
    {rc, res} = Profile.create("test0")

    assert rc == :ok
    assert %Schema{} = res

    %Schema{id: created_id} = res

    assert is_integer(created_id)
  end

  test "can detect creation of duplicate Remote Profile" do
    {rc1, res1} = Profile.create("test1")
    assert rc1 == :ok
    assert %Schema{} = res1

    {rc2, res2} = Profile.create("test1")
    assert rc2 == :duplicate
    assert is_binary(res2)
  end

  test "can update an existing Remote Profile and detect unrecognized opts" do
    {rc1, res1} = Profile.create("test2")
    assert rc1 == :ok
    assert %Schema{} = res1
    %Schema{version: vsn1} = res1

    res2 = Profile.update("test2", i2c_enable: false)
    assert is_list(res2)
    refute Keyword.get(res2, :i2c_enable)

    res3 = Profile.find("test2")
    assert %Schema{version: vsn2} = res3

    refute vsn1 == vsn2

    {rc3, res3} = Profile.update("test2", ic2_enable: false)
    assert rc3 == :unrecognized_opts
    assert Keyword.has_key?(res3, :ic2_enable)
  end

  test "can duplicate an existing Remote Profile" do
    {rc1, res1} = Profile.create("test3")
    assert rc1 == :ok
    assert %Schema{} = res1

    {rc2, res2} = Profile.duplicate("test3", "test3 copy")
    assert rc2 == :ok
    assert %Schema{} = res2
    %Schema{name: copy_name} = res2
    assert copy_name == "test3 copy"
  end
end
