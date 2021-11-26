defmodule Alfred.SeenNameTest do
  use ExUnit.Case, async: true
  use Should
  use Alfred.NamesAid

  @moduletag alfred: true, alfred_seen_name: true

  alias Alfred.SeenName

  setup_all do
    {:ok, %{make_name: [type: :imm]}}
  end

  setup [:name_add]

  describe "Alfred.SeenName.validate/1" do
    test "verifies a default SeenName is invalid" do
      res = %SeenName{} |> SeenName.validate()
      should_be_struct(res, SeenName)
      should_be_equal(res.valid?, false)
    end

    test "detects invalid seen_at", %{name: name} do
      res = %SeenName{name: name, seen_at: {:error, :datetime}} |> SeenName.validate()
      should_be_struct(res, SeenName)
      should_be_equal(res.valid?, false)
    end

    test "detects invalid ttl_ms", %{name: name} do
      utc_now = DateTime.utc_now()
      res = %SeenName{name: name, seen_at: utc_now, ttl_ms: 0} |> SeenName.validate()
      should_be_struct(res, SeenName)
      should_be_equal(res.valid?, false)
    end

    test "verifies a well formed SeenName", %{name: name} do
      utc_now = DateTime.utc_now()
      res = %SeenName{name: name, seen_at: utc_now, ttl_ms: 1000} |> SeenName.validate()
      should_be_struct(res, SeenName)
      should_be_equal(res.valid?, true)
    end

    test "verifies a list of SeenNames" do
      template = %SeenName{ttl_ms: 1000, seen_at: DateTime.utc_now()}
      list = for _ <- 1..10, do: %SeenName{template | name: NamesAid.unique("seenname")}

      list = [%SeenName{}] ++ list

      res = SeenName.validate(list)
      should_be_non_empty_list_with_length(res, 10)
    end
  end

  def name_add(ctx), do: NamesAid.make_name(ctx)
end
