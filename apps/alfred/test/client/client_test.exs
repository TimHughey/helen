defmodule Alfred.UseTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_client: true

  describe "Alfred.__using__/1" do
    test "uses Alfred.Name when execute or status features present in use_opts" do
      attributes = Alfred.Client.__info__(:attributes)

      attribute_count = Enum.count(attributes, fn {key, _val} -> to_string(key) =~ "alfred" end)

      assert attribute_count == 3
    end
  end
end
