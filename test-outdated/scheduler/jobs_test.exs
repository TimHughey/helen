defmodule JobsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  # import ExUnit.CaptureLog

  @moduletag :jobs

  setup_all do
    :ok
  end

  test "the truth will set you free" do
    assert true === true
    refute false
  end
end
