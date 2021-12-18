defmodule Alfred.SeenNameTest do
  use ExUnit.Case, async: true
  use Should

  import Alfred.NamesAid, only: [name_add: 1, unique: 1]

  @moduletag alfred: true, alfred_seen_name: true

  alias Alfred.SeenName

  setup_all do
    {:ok, %{name_add: [type: :imm]}}
  end

  setup [:name_add]

  defmacro assert_seen_name(x, want_kv?) do
    quote location: :keep, bind_quoted: [x: x, want_kv: want_kv?] do
      want_struct = Alfred.SeenName

      Should.Be.Struct.with_all_key_value(x, want_struct, want_kv)
    end
  end

  describe "Alfred.SeenName.validate/1" do
    test "verifies a default SeenName is invalid" do
      %SeenName{}
      |> SeenName.validate()
      |> assert_seen_name(valid?: false)
    end

    test "detects invalid seen_at", %{name: name} do
      %SeenName{name: name, seen_at: {:error, :datetime}}
      |> SeenName.validate()
      |> assert_seen_name(valid?: false)
    end

    test "detects invalid ttl_ms", %{name: name} do
      utc_now = DateTime.utc_now()

      %SeenName{name: name, seen_at: utc_now, ttl_ms: 0}
      |> SeenName.validate()
      |> assert_seen_name(valid?: false)
    end

    test "verifies a well formed SeenName", %{name: name} do
      utc_now = DateTime.utc_now()

      %SeenName{name: name, seen_at: utc_now, ttl_ms: 1000}
      |> SeenName.validate()
      |> assert_seen_name(valid?: true)
    end

    test "verifies a list of SeenNames" do
      template = %SeenName{ttl_ms: 1000, seen_at: DateTime.utc_now()}
      list = for _ <- 1..10, do: %SeenName{template | name: unique("seenname")}

      invalid_seen_name = %SeenName{}

      [invalid_seen_name | list]
      |> SeenName.validate()
      # invalid SeenName should not be in count
      |> Should.Be.List.with_length(10)
    end
  end
end
