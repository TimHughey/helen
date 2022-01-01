defmodule ShouldUsing do
  use Should

  def call_pretty_puts(x), do: pretty_puts(x)
end

defmodule ShouldTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  describe "Should.pretty_puts/1" do
    test "outputs pretty verison of arg" do
      require Should

      arg1 = %{hello: :doctor, yesterday: :tomorrow}

      assert capture_io(fn -> Should.pretty_puts(arg1) end) =~ ~r/hello|doctor/
    end
  end

  describe "Should.__using__/1" do
    test "outputs pretty verison of arg" do
      arg1 = %{hello: :doctor, yesterday: :tomorrow}

      assert capture_io(fn -> ShouldUsing.call_pretty_puts(arg1) end) =~ ~r/hello|doctor/
    end
  end
end
