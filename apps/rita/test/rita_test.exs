defmodule RitaTest do
  use ExUnit.Case

  test "can Rita connect to the database" do
    rc = Application.ensure_started(:rita)
    assert :ok == rc
  end
end
